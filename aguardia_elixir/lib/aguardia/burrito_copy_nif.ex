defmodule Aguardia.BurritoCopyNIF do
  @moduledoc """
  Custom Burrito build step that copies the libsalty2 NIF into the Burrito build directory,
  along with bundled libsodium to make the binary self-contained.

  This step is necessary because:
  1. We use `skip_nifs: true` to prevent Burrito from trying to recompile NIFs
     (which would require complex cross-compilation setup)
  2. When `skip_nifs` is true, Burrito doesn't copy the NIF files automatically
  3. We need to manually copy the NIF from our build to Burrito's work directory
  4. Burrito uses musl-based ERTS, so we bundle libsodium and use patchelf to set rpath

  This step should be added to the `patch` phase (post) in the Burrito config:

      extra_steps: [
        patch: [post: [Aguardia.BurritoCopyNIF]]
      ]

  Requirements:
  - patchelf must be installed on the build system (apt install patchelf)
  - libsodium must be installed on the build system
  """

  alias Burrito.Builder.Context
  alias Burrito.Builder.Step

  @behaviour Step

  @impl Step
  def execute(%Context{} = context) do
    IO.puts("--> Aguardia.BurritoCopyNIF: Copying libsalty2 NIF and bundling libsodium...")

    # Find the NIF in the prod build directory
    app_path = File.cwd!()
    build_lib_path = Path.join([app_path, "_build", "prod", "lib"])

    # Find libsalty2 directory in the BUILD path (source of NIF)
    build_libsalty2_dir =
      case find_libsalty2_dir(build_lib_path) do
        {:ok, dir} -> dir
        {:error, reason} -> raise "Failed to find libsalty2 in build: #{reason}"
      end

    src_nif = Path.join([build_libsalty2_dir, "priv", "salty_nif.so"])

    # Find libsalty2 directory in the WORK_DIR (destination - has version suffix like libsalty2-0.3.0)
    work_lib_path = Path.join(context.work_dir, "lib")

    work_libsalty2_dir =
      case find_libsalty2_dir(work_lib_path) do
        {:ok, dir} -> dir
        {:error, reason} -> raise "Failed to find libsalty2 in work_dir: #{reason}"
      end

    libsalty2_name = Path.basename(work_libsalty2_dir)

    unless File.exists?(src_nif) do
      raise """
      libsalty2 NIF not found at: #{src_nif}

      Make sure to compile the project before building the release:
        MIX_ENV=prod mix deps.compile libsalty2
        MIX_ENV=prod mix compile

      Then run:
        MIX_ENV=prod mix release
      """
    end

    # Create destination directory in Burrito's work directory
    dest_dir = Path.join([context.work_dir, "lib", libsalty2_name, "priv"])
    dest_nif = Path.join(dest_dir, "salty_nif.so")

    File.mkdir_p!(dest_dir)
    File.cp!(src_nif, dest_nif)
    IO.puts("--> Copied NIF to #{dest_nif}")

    # Now bundle musl-compiled libsodium and patch the NIF's rpath
    bundle_musl_libsodium(dest_dir, dest_nif)

    IO.puts("--> NIF bundling complete")
    context
  end

  @doc """
  Bundle musl-compiled libsodium.so alongside the NIF and use patchelf to set rpath.

  Burrito uses musl-based ERTS, so we need a musl-compiled libsodium, not glibc.
  We download Alpine Linux's libsodium package which is musl-compiled.
  """
  def bundle_musl_libsodium(dest_dir, nif_path) do
    # Download and extract Alpine's musl-compiled libsodium
    app_path = File.cwd!()
    cache_dir = Path.join([app_path, "priv", "musl_libs_cache"])
    File.mkdir_p!(cache_dir)

    libsodium_so = Path.join(cache_dir, "libsodium.so.23")

    # Download if not cached
    unless File.exists?(libsodium_so) do
      IO.puts("--> Downloading Alpine's musl-compiled libsodium...")

      # Alpine 3.16 has libsodium 1.0.18 which provides libsodium.so.23
      apk_url = "https://dl-cdn.alpinelinux.org/alpine/v3.16/main/x86_64/libsodium-1.0.18-r0.apk"
      apk_file = Path.join(cache_dir, "libsodium.apk")

      # Download APK
      case System.cmd("curl", ["-sL", apk_url, "-o", apk_file], stderr_to_stdout: true) do
        {_, 0} -> :ok
        {output, code} -> raise "Failed to download libsodium APK (exit #{code}): #{output}"
      end

      # Extract APK (it's a gzipped tar)
      extract_dir = Path.join(cache_dir, "extracted")
      File.mkdir_p!(extract_dir)

      case System.cmd("tar", ["-xf", apk_file, "-C", extract_dir], stderr_to_stdout: true) do
        {_, 0} -> :ok
        {output, code} -> raise "Failed to extract APK (exit #{code}): #{output}"
      end

      # Find and copy libsodium.so.23
      extracted_lib = Path.join([extract_dir, "usr", "lib", "libsodium.so.23.3.0"])

      unless File.exists?(extracted_lib) do
        {find_output, _} =
          System.cmd("find", [extract_dir, "-name", "libsodium.so*"], stderr_to_stdout: true)

        raise "Could not find libsodium in extracted APK. Found: #{find_output}"
      end

      File.cp!(extracted_lib, libsodium_so)

      # Cleanup
      File.rm_rf!(extract_dir)
      File.rm!(apk_file)
    end

    # Copy to destination
    libsodium_dest = Path.join(dest_dir, "libsodium.so.23")
    File.cp!(libsodium_so, libsodium_dest)
    IO.puts("--> Bundled musl libsodium")

    # Use patchelf to set the NIF's rpath to $ORIGIN so it finds libsodium in the same dir
    case System.cmd("patchelf", ["--set-rpath", "$ORIGIN", nif_path], stderr_to_stdout: true) do
      {_, 0} ->
        IO.puts("--> Patched NIF rpath to $ORIGIN")

      {output, code} ->
        raise "patchelf failed with exit code #{code}: #{output}"
    end
  end

  @doc """
  Find the libsalty2 directory in the build path.
  Returns {:ok, path} or {:error, reason}.
  """
  def find_libsalty2_dir(build_lib_path) do
    case File.ls(build_lib_path) do
      {:ok, dirs} ->
        case Enum.find(dirs, &String.starts_with?(&1, "libsalty2")) do
          nil -> {:error, "libsalty2 not found in #{build_lib_path}"}
          dir -> {:ok, Path.join(build_lib_path, dir)}
        end

      {:error, reason} ->
        {:error, "Cannot list #{build_lib_path}: #{inspect(reason)}"}
    end
  end
end
