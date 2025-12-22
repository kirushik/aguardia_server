const WS_CLOSE_NORMAL = 1000

export class HulypulseClient {
  constructor(url) {
    this.url = url
    this.ws = null
    this.closed_manually = false
    this.reconnectTimeout = undefined
    this.RECONNECT_INTERVAL_MS = 3000

    this.recieve_counter = 0
    this.SEND_TIMEOUT_MS = 3000
    this.correlationId = 1
    this.pending = new Map()

    this.onmessage_fn = null
    this.onmessage_login_fn = null

    this.ondisconnect_fn = null
    this.onconnect_fn = null

    this.connect_status = false;
  }

  setOnMessage(fn) { this.onmessage_fn = fn }
  setOnMessageLogin(fn) { this.onmessage_login_fn = fn }

  setOnConnect(fn) { this.onconnect_fn = fn }
  setOnDisconnect(fn) { this.ondisconnect_fn = fn }

  async connect() {
    await new Promise((resolve) => {
      const ws = new WebSocket(this.url.toString())
      this.ws = ws
      ws.onopen = () => {
        console.warn("onopen", this.connect_status);
        if(!this.connect_status && this.onconnect_fn) this.onconnect_fn();
        this.connect_status = true;
        resolve();
      }
      ws.onerror = () => {
        console.warn("onerror",this.connect_status);
        if(this.connect_status && this.ondisconnect_fn) this.ondisconnect_fn();
        this.connect_status = false;
        this.reconnect();
      }
      ws.onclose = () => {
        console.warn("onclose",this.connect_status);
        if(this.connect_status && this.ondisconnect_fn) this.ondisconnect_fn();
        this.connect_status = false;
        this.reconnect();
      }
      ws.onmessage = async (event) => {
        let raw = event.data;

        if (raw === 'ping') { this.ws && this.ws.send('pong'); 
              console.warn("Send pong");
          return; }
        if (raw === 'pong') return;
        if (raw === 'Failed to route') return;
        
        // String message - xz
        if (typeof raw === "string") return this.onmessage_login_fn && this.onmessage_login_fn(raw);

        if (raw instanceof Blob) raw = new Uint8Array(await raw.arrayBuffer());
        if (raw instanceof ArrayBuffer || raw instanceof Uint8Array) raw = new Uint8Array(raw);
        else {
          console.warn(`❌ Invalid data type "${typeof raw}", use ws.binaryType='arraybuffer';`);
          return;
        }

        if (raw.length < 5) {
          console.warn("❌ Packet too short");
          return;
        }

        let user_id = (raw[3] << 24) | (raw[2] << 16) | (raw[1] << 8)  | raw[0];
        let encrypted = raw.slice(4);

        if(!AG?.KEYS?.[user_id]) {
          console.warn(`❌ User ${user_id} not found in KEYS`);
          return;
        }

        // verify_and_decrypt(packet, x_my_secret, x_he_public, ed_he_public, delta_sec, now_sec) {
        let bin = crypto25519.verify_and_decrypt(
          encrypted,
          AG.my_x_secret,
          AG.KEYS[user_id].x,
          AG.KEYS[user_id].ed,
          5,
          Math.floor(Date.now() / 1000) );
        if (!bin || !bin.length) {
          // console.warn("❌ decrypt/verify failed");
          pr("❌ decrypt/verify failed from user " + user_id);
          pr("❌ my_x_secret: " + U8hex(AG.my_x_secret));
          pr("❌ X: " + U8hex(AG.KEYS[user_id].x));
          pr("❌ ed: " + U8hex(AG.KEYS[user_id].ed));
          pr("❌ encrypted: " + U8hex(encrypted));
          return;
        }

        // TODO
        this.recieve_counter++;

        if (bin.length < 4) {
          console.warn("❌ Empty decrypted packet");
          return;
        }
        const id = (bin[1] << 8) | bin[0];
        const cmd = bin[2];
        const body = bin.subarray(3);

        const raw_text = new TextDecoder().decode(body);
        if(raw_text != "pong") console.log(`🔐 Received from ${user_id} with cmd ${cmd} and message_id ${id} and text=[${raw_text}]`);

        if(cmd == 0x01) { // пришел ответ
          const pending = this.pending.get(id)
          if (pending) {
            clearTimeout(pending.send_timeout)
            this.pending.delete(id)
            // pr(`✅ 0x01 received answer #${id} from ${user_id}`);
            let json = null;
            try {
              json = new TextDecoder().decode(body);
              json = JSON.parse(json);
            } catch(e) { }
            pending.resolve( json );
          } else {
            console.warn(`❌ Unknown response ${id} from ${user_id}`);
          }
          return;
        }

        if(cmd == 0x00) { // ответить с тем же id
          const result = this.onmessage_fn && await this.onmessage_fn(user_id, cmd, body);
          pr(`✅ 0x01 answering #${id} to ${user_id} [${result}]`);
          if(result) await this.send_secret_answer(0x01, result, user_id, id);
        }

      }
    })
  }

  reconnect() {
    if (this.reconnectTimeout) clearTimeout(this.reconnectTimeout)
    if (this.closed_manually) return;
    this.reconnectTimeout = setTimeout(() => { this.connect() }, this.RECONNECT_INTERVAL_MS)
  }

  close() {
    this.closed_manually = true
    if (this.reconnectTimeout) clearTimeout(this.reconnectTimeout)
    this.reconnectTimeout = undefined
    this.ws && this.ws.close()
  }

  static async connect(url) {
    const client = new HulypulseClient(url)
    await client.connect()
    return client
  }

  async send(msg) {

    if (this.closed_manually) {
      this.closed_manually = false_bytes
      if (!this.ws || this.ws.readyState > 1) await this.connect();
    }

    console.warn("Send:", msg);
    this.ws.send(msg);
  }


// ==================================================

  toBytes(v) {
    if (v instanceof Uint8Array) return v;
    if (typeof v === 'string') return new TextEncoder().encode(v); // строка → UTF-8 байты
    if (Array.isArray(v)) return new Uint8Array(v) // обычный JS-массив чисел
    if (v instanceof ArrayBuffer) return new Uint8Array(v);
    throw new Error('Unknown data')
  }

  async make_payload(cmd, msg, to, id) {

    if (! AG?.my_id) throw new Error(`Missing AG.my_id`);
    if (! AG?.KEYS) throw new Error(`Missing AG.KEYS`);
    if (! AG.KEYS[AG.my_id]) throw new Error(`Missing my KEYS (${h(AG.my_id)})`);
    // if (! to) throw new Error(`Missing to`);
    if (! AG.KEYS[to]) throw new Error(`Missing to KEYS (${h(to)})`);

    if (! AG?.KEYS || !AG?.my_id || !AG.KEYS[AG.my_id] || !AG.KEYS[to])
      throw new Error(`Missing KEYS (${h(to)})`);

    if (this.closed_manually) {
      this.closed_manually = false;
      if (!this.ws || this.ws.readyState > 1) await this.connect()
    }

    if(id==undefined) {
      this.correlationId = (this.correlationId + 1) & 0xFFFF; //  | 1; not zero?     
      id = this.correlationId;
    }

    const body = this.toBytes(msg);

    // <to>[ id2 | cmd1 | body ]
    let inner = new Uint8Array(3 + body.length);
    new DataView(inner.buffer).setUint16(0, id, true); // id 2
    inner[2] = cmd; // cmd 1
    inner.set(body, 3);

    let now = Math.floor(Date.now());
    // inner = new Uint8Array(inner);
    // pr("⏳ encrypt...");

    // encrypt_and_sign(data, x_my_secret, ed_my_secret_bytes, x_he_public, now_sec) {

    // console.log('Sending secret message to', to, 'with cmd', cmd, 'and id', id);
    const encoded = crypto25519.encrypt_and_sign(
        inner, 
        AG.my_x_secret,
        AG.my_ed_secret, 
        AG.KEYS[to].x,
        Math.floor(Date.now() / 1000)
    );
    const payload = new Uint8Array(4 + encoded.length);
    new DataView(payload.buffer).setUint32(0, to >>> 0, true);
    payload.set(encoded, 4);
    return payload;
  }

  async server_request(r) {
      return this.send_secret(0x00, JSON.stringify(r), 0);
  }

  async send_secret(cmd, msg, to, id, timeout_ms) {

    if(!id) {
      this.correlationId = (this.correlationId + 1) & 0xFFFF; //  | 1; not zero?     
      id = this.correlationId;
    }

    const payload = await this.make_payload(cmd, msg, to, id);

    return await new Promise((resolve, reject) => {

      if (this.closed_manually || !this.ws || this.ws.readyState !== WebSocket.OPEN) {
        resolve({ error: 'WebSocket is not open.' })
        return
      }

      const sendTimeout = setTimeout(() => {
        const pending = this.pending.get(id)
        if (pending) {
          pending.resolve({ error: 'Timeout waiting for response' })
          this.pending.delete(id)
        }
      }, timeout_ms || this.SEND_TIMEOUT_MS)

      this.pending.set(id, { resolve, reject, send_timeout: sendTimeout })
      console.warn("send_secret:", msg);
      this.ws.send(payload);
    })
  }

  async send_secret_answer(cmd, msg, to, id) {
    if(!id) throw new Error('Missing id for answer');
    const payload = await this.make_payload(cmd, msg, to, id);
    console.warn("send_secret_answer:", msg);
    this.ws.send(payload);
  }

}