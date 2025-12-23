#!/bin/bash
# ==============================================================
# Aguardia Elixir Test Runner
# ==============================================================
#
# This script runs the comprehensive test suite for the Aguardia
# Elixir server implementation.
#
# Prerequisites:
# - Elixir 1.14+ and Erlang/OTP 25+
# - libsodium installed (for enacl NIF)
# - PostgreSQL running with test database
#
# Usage:
#   ./run_tests.sh              # Run all tests
#   ./run_tests.sh crypto       # Run only crypto tests
#   ./run_tests.sh commands     # Run only command tests
#   ./run_tests.sh protocol     # Run only protocol tests
#   ./run_tests.sh fuzzing      # Run only fuzzing tests
#   ./run_tests.sh load         # Run only load tests
#   ./run_tests.sh quick        # Run quick tests (exclude load)
#   ./run_tests.sh setup        # Setup test database only
#
# ==============================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored message
print_msg() {
    echo -e "${2}${1}${NC}"
}

# Print header
print_header() {
    echo ""
    echo -e "${BLUE}=============================================================="
    echo -e "$1"
    echo -e "==============================================================${NC}"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check Elixir
    if ! command -v elixir &> /dev/null; then
        print_msg "ERROR: Elixir is not installed" "$RED"
        exit 1
    fi
    print_msg "✓ Elixir: $(elixir --version | head -1)" "$GREEN"

    # Check Mix
    if ! command -v mix &> /dev/null; then
        print_msg "ERROR: Mix is not installed" "$RED"
        exit 1
    fi
    print_msg "✓ Mix available" "$GREEN"

    # Check PostgreSQL
    if ! command -v psql &> /dev/null; then
        print_msg "WARNING: PostgreSQL client not found" "$YELLOW"
    else
        print_msg "✓ PostgreSQL client available" "$GREEN"
    fi

    # Check libsodium
    if ! ldconfig -p 2>/dev/null | grep -q libsodium; then
        if ! pkg-config --exists libsodium 2>/dev/null; then
            print_msg "WARNING: libsodium may not be installed" "$YELLOW"
            print_msg "  Install with: apt-get install libsodium-dev (Debian/Ubuntu)" "$YELLOW"
            print_msg "             or: brew install libsodium (macOS)" "$YELLOW"
        fi
    else
        print_msg "✓ libsodium available" "$GREEN"
    fi
}

# Setup dependencies
setup_deps() {
    print_header "Setting Up Dependencies"

    print_msg "Fetching dependencies..." "$BLUE"
    mix deps.get

    print_msg "Compiling dependencies..." "$BLUE"
    mix deps.compile
}

# Setup test database
setup_database() {
    print_header "Setting Up Test Database"

    print_msg "Creating test database..." "$BLUE"
    MIX_ENV=test mix ecto.create || true

    print_msg "Running migrations..." "$BLUE"
    MIX_ENV=test mix ecto.migrate

    print_msg "✓ Database ready" "$GREEN"
}

# Run specific test file
run_test_file() {
    local test_file=$1
    local test_name=$2

    print_header "Running $test_name Tests"

    MIX_ENV=test mix test "$test_file" --trace
}

# Run all tests
run_all_tests() {
    print_header "Running All Tests"

    MIX_ENV=test mix test --trace
}

# Run quick tests (exclude load tests)
run_quick_tests() {
    print_header "Running Quick Tests (excluding load tests)"

    MIX_ENV=test mix test --exclude load --trace
}

# Run tests with coverage
run_with_coverage() {
    print_header "Running Tests with Coverage"

    MIX_ENV=test mix coveralls
}

# Main
main() {
    local command=${1:-all}

    print_header "Aguardia Elixir Test Suite"

    case $command in
        setup)
            check_prerequisites
            setup_deps
            setup_database
            print_msg "\n✓ Setup complete!" "$GREEN"
            ;;
        crypto)
            setup_deps
            setup_database
            run_test_file "test/aguardia/crypto_test.exs" "Crypto"
            ;;
        commands)
            setup_deps
            setup_database
            run_test_file "test/aguardia_web/commands_test.exs" "Commands"
            ;;
        protocol)
            setup_deps
            setup_database
            run_test_file "test/aguardia_web/protocol_test.exs" "Protocol"
            ;;
        fuzzing)
            setup_deps
            setup_database
            run_test_file "test/aguardia/fuzzing_test.exs" "Fuzzing"
            ;;
        load)
            setup_deps
            setup_database
            run_test_file "test/aguardia/load_test.exs" "Load"
            ;;
        email)
            setup_deps
            setup_database
            run_test_file "test/aguardia/email_codes_test.exs" "Email Codes"
            ;;
        quick)
            setup_deps
            setup_database
            run_quick_tests
            ;;
        coverage)
            setup_deps
            setup_database
            run_with_coverage
            ;;
        all)
            check_prerequisites
            setup_deps
            setup_database
            run_all_tests
            ;;
        *)
            print_msg "Unknown command: $command" "$RED"
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  all       - Run all tests (default)"
            echo "  setup     - Setup test environment only"
            echo "  crypto    - Run crypto compatibility tests"
            echo "  commands  - Run command handler tests"
            echo "  protocol  - Run protocol compliance tests"
            echo "  fuzzing   - Run input fuzzing tests"
            echo "  load      - Run load/performance tests"
            echo "  email     - Run email codes tests"
            echo "  quick     - Run quick tests (exclude load)"
            echo "  coverage  - Run tests with coverage report"
            exit 1
            ;;
    esac

    print_header "Test Run Complete"
    print_msg "✓ All requested tests finished" "$GREEN"
}

# Run main with all arguments
main "$@"
