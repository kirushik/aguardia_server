use rand::RngCore;
use rand::rngs::OsRng;
use std::time::{SystemTime, UNIX_EPOCH};
use x25519_dalek::{x25519, X25519_BASEPOINT_BYTES};
use ed25519_dalek::{SigningKey, VerifyingKey, Signature, Signer, Verifier};
use chacha20poly1305::{ aead::{Aead}, XChaCha20Poly1305, XNonce, Key, KeyInit };

// base64
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
#[allow(dead_code)]
pub fn bin_to_base64(data: &[u8]) -> String {
    URL_SAFE_NO_PAD.encode(data)
}

#[allow(dead_code)]
pub fn base64_to_bin(s: &str) -> Result<Vec<u8>, base64::DecodeError> {
    URL_SAFE_NO_PAD.decode(s)
}

#[allow(dead_code)]
pub fn base64_u8_32(s: &str) -> Result<[u8; 32], base64::DecodeError> {
    let vec = URL_SAFE_NO_PAD.decode(s)?;
    let array: [u8; 32] = vec.as_slice().try_into().map_err(|_| base64::DecodeError::InvalidLength)?;
    Ok(array)
}

// pub fn sign(data: &[u8], sk: &SigningKey) -> [u8; 64] {
//     sk.sign(data).to_bytes()
// }
pub fn verify(data: &[u8], sig: &[u8; 64], pk: &VerifyingKey) -> bool {
    pk.verify(data, &Signature::from_bytes(&sig)).is_ok()
}
// pub fn x25519_shared_key(my_secret: [u8; 32], their_public: [u8; 32]) -> [u8; 32] {
//     x25519(my_secret, their_public)
// }

// Encode - Decode
pub fn get_unixtime() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs()
}

pub fn nonce_from_u64(n: u64) -> XNonce {
    let mut out = [0u8; 24];
    let b = n.to_le_bytes();
    out[0..8].copy_from_slice(&b);
    out[8..16].copy_from_slice(&b);
    out[16..24].copy_from_slice(&b);
    XNonce::from_slice(&out).clone()
}

pub fn encrypt_message(
    their_public: &[u8; 32],
    my_secret: &[u8; 32],
    plaintext: &[u8],
    nonce: &u64,
) -> Vec<u8> {
    let shared = x25519(*my_secret, *their_public); // x25519_shared_key(*my_secret, *their_public);
    let key = Key::from_slice(&shared);
    let cipher = XChaCha20Poly1305::new(key);
    let nonce = nonce_from_u64(*nonce);
    cipher.encrypt(&nonce, plaintext).expect("encryption failed")
}

pub fn decrypt_message(
    their_public: &[u8; 32],
    my_secret: &[u8; 32],
    encrypted: &Vec<u8>,
    nonce: &u64,
) -> Vec<u8> {
    let shared = x25519(*my_secret, *their_public); // x25519_shared_key(*my_secret, *their_public);
    let key = Key::from_slice(&shared);
    let cipher = XChaCha20Poly1305::new(key);
    let nonce = nonce_from_u64(*nonce);
    cipher
        .decrypt(&nonce, encrypted.as_ref())
        .expect("decryption failed")
}


// Generate key

pub fn seed() -> [u8; 32] {
    let mut seed = [0u8; 32];
    OsRng.fill_bytes(&mut seed);
    seed
}

pub fn x25519_secret(seed: &[u8; 32]) -> [u8; 32] {
    let mut sk = seed.clone();
    sk[0]  &= 248;
    sk[31] &= 127;
    sk[31] |= 64;
    sk
}

pub fn x25519_public(secret: &[u8; 32]) -> [u8; 32] {
    x25519(*secret, X25519_BASEPOINT_BYTES)
}

pub fn ed25519_secret(seed: &[u8; 32]) -> SigningKey {
    SigningKey::from_bytes(seed)
}
pub fn ed25519_public(sk: &SigningKey) -> VerifyingKey {
    VerifyingKey::from(sk)
}


// All

#[allow(dead_code)]
pub fn encrypt_and_sign(
    data: &[u8],
    x_my_secret: &[u8; 32],
    ed_my_secret: &SigningKey,
    x_he_public: &[u8; 32],
) -> Vec<u8> {
    let nonce = get_unixtime();
    let ciphertext = encrypt_message(x_he_public, x_my_secret, data, &nonce);
    let mut packet = Vec::with_capacity(8 + ciphertext.len() + 64);
    packet.extend_from_slice(&nonce.to_le_bytes());
    packet.extend_from_slice(&ciphertext);
    let sig = ed_my_secret.sign(&packet).to_bytes();
    packet.extend_from_slice(&sig);
    packet
}

#[derive(Debug)]
pub enum DecryptError {
    BadNonce,
    BadSignature,
    BadFormat,
}

pub fn verify_and_decrypt(
    packet: &[u8],
    x_my_secret: &[u8; 32],
    x_he_public: &[u8; 32],
    ed_he_public: &VerifyingKey,
    max_nonce_skew: u64, // 30 sec
) -> Result<Vec<u8>, DecryptError> {

    if packet.len() < 8 + 64 { return Err(DecryptError::BadFormat); }

    let (nonce_and_cipher, sig_bytes) = packet.split_at(packet.len() - 64);
    if nonce_and_cipher.len() < 8 { return Err(DecryptError::BadFormat); }
    let mut sig_arr = [0u8; 64];
    sig_arr.copy_from_slice(sig_bytes);

    if !ed_he_public.verify(nonce_and_cipher, &Signature::from_bytes(&sig_arr)).is_ok() { return Err(DecryptError::BadSignature); }
   
    let mut nonce_arr = [0u8; 8];
    nonce_arr.copy_from_slice(&nonce_and_cipher[0..8]);
    let nonce = u64::from_le_bytes(nonce_arr);

    // check nonce == unixtime
    if max_nonce_skew > 0 {
        let now = get_unixtime();
        if now.abs_diff(nonce) > max_nonce_skew { return Err(DecryptError::BadNonce); }
    }

    let ciphertext = &nonce_and_cipher[8..];
    let plaintext = decrypt_message(x_he_public, x_my_secret, &ciphertext.to_vec(), &nonce);
    Ok(plaintext)
}



// ==================================================

#[cfg(test)]
mod tests {
    use hex::FromHex;
    use super::*; 

    #[test]
    fn base64_encode_test() {
        let data = <[u8; 32]>::from_hex("481179010ae65f2bc7508430ac270386953aa75930042e22c184b78b41e95747").unwrap();
        let encoded = bin_to_base64(&data);
        assert_eq!(encoded, "SBF5AQrmXyvHUIQwrCcDhpU6p1kwBC4iwYS3i0HpV0c");
    }

    #[test]
    fn base64_decode_test() {
        let data = "SBF5AQrmXyvHUIQwrCcDhpU6p1kwBC4iwYS3i0HpV0c"; 
        let decoded = base64_to_bin(&data).unwrap();
        assert_eq!(decoded, <Vec<u8>>::from_hex("481179010ae65f2bc7508430ac270386953aa75930042e22c184b78b41e95747").unwrap());
    }
        
    #[test]
    fn generate_x_sk() {
        let seed = <[u8; 32]>::from_hex("5e8b7ecfe76faa5022ae7884f7f148d0b801e58ce8783d99bee69fb9e8029f71").unwrap();
        let sk = x25519_secret(&seed);
        assert_eq!(sk, <[u8; 32]>::from_hex("588b7ecfe76faa5022ae7884f7f148d0b801e58ce8783d99bee69fb9e8029f71").unwrap());
    }

    #[test]
    fn generate_x_pk() {
        let sk = <[u8; 32]>::from_hex("588b7ecfe76faa5022ae7884f7f148d0b801e58ce8783d99bee69fb9e8029f71").unwrap();
        let pk = x25519_public(&sk);
        assert_eq!(pk, <[u8; 32]>::from_hex("00525d3ade51dbfb083b3c1fdf63b4a83fe5bef9f95deaf5f3278ccf816a7e0a").unwrap());
    }

    #[test]
    fn encrypt_message_test() {       
        let x_sk_my = <[u8; 32]>::from_hex("481179010ae65f2bc7508430ac270386953aa75930042e22c184b78b41e95747").unwrap();
        // let x_pk_my = <[u8; 32]>::from_hex("af2af6e676e7801fc0b150733f79a20d6897b1c9cb4df3f651df81b180ca086e").unwrap();
        // let x_sk_he = <[u8; 32]>::from_hex("a0d70cf83f6db80d093646d66fee62c422a1e160c3d4cd52ef44fd0f2698127d").unwrap();
        let x_pk_he = <[u8; 32]>::from_hex("2dfb6cf139728610e7766833862dc708cf9ff38a0f7c4b55c68b3bc0cc73d536").unwrap();
        // let mut ed_sk_my = SigningKey::from_bytes(&<[u8; 32]>::from_hex("454b10b610f9a3a99cd577e6d50a9fbabaa8e50e134b250f2695d17ca446f40e").unwrap());
        // let ed_pk_my  = VerifyingKey::from_bytes(&<[u8; 32]>::from_hex("e498d275fe727bd9150b504d18b65b567516fd4ac3d0ed5e58a50475e8138d8f").unwrap()).unwrap();
        // let ed_sk_he = SigningKey::from_bytes(&<[u8; 32]>::from_hex("4163585bb6433979c67fdbac95af696f6f7868c698ecf3e48422ff5edd63735a").unwrap());
        // let ed_pk_he = VerifyingKey::from_bytes(&<[u8; 32]>::from_hex("9b77403d8e9257de07e6f59e35ace09b5479bc27eab92216a23d2b20036cc539").unwrap()).unwrap();
        let text = r#"{"key":"Какой-то текст"}"#.to_string();   
        let nonce: u64 = 1764020895;

        let enc = encrypt_message(&x_pk_he, &x_sk_my, &text.as_bytes(), &nonce);

        assert_eq!(enc, <Vec<u8>>::from_hex("1b3518ec11aab49db6a1199de6db109314419b83988897fb66dd724612def8f8ebc6ebef9a42c07eb7daef2904c0252fcd734099").unwrap());
    }

    #[test]
    fn decrypt_message_test() {
        let enc = <Vec<u8>>::from_hex("1b3518ec11aab49db6a1199de6db109314419b83988897fb66dd724612def8f8ebc6ebef9a42c07eb7daef2904c0252fcd734099").unwrap();
        let x_pk_my = <[u8; 32]>::from_hex("af2af6e676e7801fc0b150733f79a20d6897b1c9cb4df3f651df81b180ca086e").unwrap();
        let x_sk_he = <[u8; 32]>::from_hex("a0d70cf83f6db80d093646d66fee62c422a1e160c3d4cd52ef44fd0f2698127d").unwrap();
        let nonce: u64 = 1764020895;

        let dec = decrypt_message(&x_pk_my, &x_sk_he, &enc, &nonce);

        assert_eq!(dec, r#"{"key":"Какой-то текст"}"#.as_bytes());
    }

    #[test]
    fn sign_test() {
        let ed_sk_my = SigningKey::from_bytes(&<[u8; 32]>::from_hex("454b10b610f9a3a99cd577e6d50a9fbabaa8e50e134b250f2695d17ca446f40e").unwrap());

        let enc = <Vec<u8>>::from_hex("1b3518ec11aab49db6a1199de6db109314419b83988897fb66dd724612def8f8ebc6ebef9a42c07eb7daef2904c0252fcd734099").unwrap();
        let nonce: u64 = 1764020895;
        let mut signed_data = Vec::new();
        signed_data.extend_from_slice(&nonce.to_le_bytes());
        signed_data.extend_from_slice(&enc);

        let sig = &ed_sk_my.sign(&signed_data).to_bytes();

        assert_eq!(sig.as_slice(), &<[u8; 64]>::from_hex("2ebf005211c796dc7a5f02b84e115f0fa7e1803f801f6d41c611ed419d40999b21125c7ecdc91cd83e1b398b0929ced3129db1486e3c6475a18382dc4749ed0c").unwrap());
    }

    #[test]
    fn verify_test() {        
        let ed_pk_my  = VerifyingKey::from_bytes(&<[u8; 32]>::from_hex("e498d275fe727bd9150b504d18b65b567516fd4ac3d0ed5e58a50475e8138d8f").unwrap()).unwrap();
        let signature: [u8; 64] = <[u8; 64]>::from_hex("2ebf005211c796dc7a5f02b84e115f0fa7e1803f801f6d41c611ed419d40999b21125c7ecdc91cd83e1b398b0929ced3129db1486e3c6475a18382dc4749ed0c").unwrap();
        let signed_data = <Vec<u8>>::from_hex("9fd22469000000001b3518ec11aab49db6a1199de6db109314419b83988897fb66dd724612def8f8ebc6ebef9a42c07eb7daef2904c0252fcd734099").unwrap();

        let ok = &ed_pk_my.verify(&signed_data, &Signature::from_bytes(&signature)).is_ok();

        assert_eq!(*ok, true);
    }  

    #[test]
    fn encrypt_decrypt_roundtrip() {
        let seed_my = seed();
        let x_sk_my = x25519_secret(&seed_my);
        let x_pk_my = x25519_public(&x_sk_my);

        let seed_he = seed();
        let x_sk_he = x25519_secret(&seed_he);
        let x_pk_he = x25519_public(&x_sk_he);

        let text = r#"{"key":"Какой-то текст"}"#.as_bytes();

        let data = encrypt_and_sign(text, &x_sk_my, &ed25519_secret(&seed_my), &x_pk_he);
        let out = verify_and_decrypt(&data, &x_sk_he, &x_pk_my, &ed25519_public(&ed25519_secret(&seed_my)), 10).unwrap();

        assert_eq!(out, text);
    }


}


// ==================================================
/*
    // X25519 keys
    let seed_my = seed();
    let x_sk_my = x25519_secret(&seed_my);
    let x_pk_my = x25519_public(&x_sk_my);
    println!("seed = {}", hex::encode(&seed_my));
    println!("X_ SK MY: {} {}", hex::encode(&x_sk_my), bin_to_base64(&x_sk_my));
    println!("X_ PK MY: {} {}", hex::encode(&x_pk_my), bin_to_base64(&x_pk_my));

    let seed_he = seed();
    println!("seed = {}", hex::encode(&seed_my));
    let x_sk_he = x25519_secret(&seed_he);
    let x_pk_he = x25519_public(&x_sk_he);
    println!("X_ SK HE: {} {}", hex::encode(&x_sk_he), bin_to_base64(&x_sk_he));
    println!("X_ PK HE: {} {}", hex::encode(&x_pk_he), bin_to_base64(&x_pk_he));

    // ED25519 keys
    let seed_ed_my = seed();
    println!("seed = {}", hex::encode(&seed_my));
    let mut ed_sk_my = ed25519_secret(&seed_ed_my);
    let ed_pk_my = ed25519_public(&ed_sk_my);
    println!("ED SK MY: {} {}", hex::encode(ed_sk_my.to_bytes()), bin_to_base64(&ed_sk_my.to_bytes()));
    println!("ED PK MY: {} {}", hex::encode(ed_pk_my.to_bytes()), bin_to_base64(&ed_pk_my.to_bytes()));

    let seed_ed_he = seed();
    println!("seed = {}", hex::encode(&seed_my));
    let ed_sk_he = ed25519_secret(&seed_ed_he);
    let ed_pk_he = ed25519_public(&ed_sk_he);
    println!("ED SK HE: {} {}", hex::encode(ed_sk_he.to_bytes()), bin_to_base64(&ed_sk_he.to_bytes()));
    println!("ED PK HE: {} {}", hex::encode(ed_pk_he.to_bytes()), bin_to_base64(&ed_pk_he.to_bytes()));

    let text = r#"{"key":"Какой-то текст"}"#.to_string();
    
    let nonce = get_unixtime();
    println!("nonce: {} Message: {}", &nonce, &text);
    let enc = encrypt_message(&x_pk_he, &x_sk_my, &text.as_bytes(), &nonce);
    println!("Encrypted: {}", hex::encode(&enc));
    let dec = decrypt_message(&x_pk_my, &x_sk_he, &enc, &nonce);
    let text_dec = String::from_utf8_lossy(&dec);
    println!("Decrypted [{}]: {}", (text == text_dec), &text_dec);
    // Формируем данные для подписи: nonce + ciphertext
    let mut signed_data = Vec::new();
    signed_data.extend_from_slice(&nonce.to_le_bytes());
    signed_data.extend_from_slice(&enc);
    let sig = &ed_sk_my.sign(&signed_data).to_bytes();

    // pub fn verify(data: &[u8], sig: &[u8; 64], pk: &VerifyingKey) -> bool {
//     pk.verify(data, &Signature::from_bytes(&sig)).is_ok()
// }
// pub fn x25519_shared_key(my_secret: [u8; 32], their_public: [u8; 32]) -> [u8; 32] {
//     x25519(my_secret, their_public)
// }
 use ed25519_dalek::Verifier;
 use ed25519_dalek::Signature;

    println!("Signature: {}", hex::encode(&sig));
    let ok = &ed_pk_my.verify(&signed_data, &Signature::from_bytes(&sig)).is_ok();
    // if !ed_he_public.verify(nonce_and_cipher, &Signature::from_bytes(&sig_arr)).is_ok() { return Err(DecryptError::BadSignature); }
   
    
    // verify(&signed_data, &sig, &ed_pk_my);
    println!("Verify: {}", ok);

    // let datasend = encrypt_data(
    //     &text.as_bytes(),
    //     &x_sk_my,
    //     &ed_sk_my,
    //     &x_pk_he
    // );
    // println!("\nSEND {} bytes: {}", datasend.len(), hex::encode(&datasend));

    // //  use std::thread;
    // //  use std::time::Duration;
    // //  thread::sleep(Duration::from_secs(4));

    // match decrypt_data(&datasend, &x_sk_he, &x_pk_my, &ed_pk_my, 3) {
    //     Ok(data) => {
    //         println!("\nREAD {} bytes: {}", data.len(), String::from_utf8_lossy(&data));
    //     }
    //     Err(err) => {
    //         println!("\nError: {:?}", err);
    //     }
    // }
*/