#!/bin/bash

clear

rm -f ./target/release/aguardia_server
export CARGO_PROFILE_RELEASE_DEBUG=false
RUSTFLAGS="--cfg tracing_unstable_disable -C embed-bitcode=yes -C opt-level=z -C codegen-units=1 -C panic=abort -C strip=symbols" \
cargo build --release

AG_LOGLEVEL="TRACE" \
AG_BIND_PORT=8112 \
AG_BIND_HOST="0.0.0.0" \
AG_HEARTBEAT_TIMEOUT=90 \
AG_BIND_PING_TIMEOUT=30 \
AG_SEED_X="111111111111111111 secret 11111111111111111111111111111111111111" \
AG_SEED_ED="2222222222222222222 secret 2222222222222222222222222222222222222" \
AG_SMTP2GO_LOGIN="lleo.me" \
AG_SMTP2GO_PASSWORD="my_password" \
AG_SMTP2GO_FROM="noreply@lleo.me" \
./target/release/aguardia_server

exit

Протокол:

данные: n байт
подпись: 64 байта

внутри данных:
    кому (от кого): 4 байта (если 0 то серверу)
    id: 2 байта (уникальный номер сообщения)
    данные: n-6
        если первый байт данных 0, то это команда
            команда: 1 байт:
                0x01 - чтение файла, далее String имя файла (utf8)
                0x02 - запись файла, далее String имя файла (utf8), далее содержимое файла

если пришло устройство:
    - проверка, если ли в базе такой ed25519 ключ
        - если нет, то вернуть ошибку и закрыть соединение
        - если да, начать цикл чтения сообщений от устройства

если пришел пользователь:
    - проверка, если ли в базе такой ed25519 ключ
        - если нет, то цикл лимб (без шифрования, проверяем только подпись ed25519):
            - ждать команду регистрации: {"action": "register_start", "email": email}
            - выслать проверочный код на email
            - ждать ввод проверочного кода: {"action": "register_verify", "verify_code": code, "x25519": x25519}
            - если код неверный, закрыть соединение и выдать ошибку
            - создать/обновить запись в базе
        - если да, начать цикл чтения сообщений от устройства

