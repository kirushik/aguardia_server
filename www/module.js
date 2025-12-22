import init, * as crypto25519 from "./wasm_crypto25519.js";
import { HulypulseClient } from './ws_client.js'

async function main() {
    await init("./wasm_crypto25519_bg.wasm");
    window.crypto25519 = crypto25519;
    console.log("WASM initialized", Object.keys(crypto25519));

    pr("clear");
    INIT();

    AG.load_keys(); // прочли ключи

    // await AG.load_server_keys(); // прочли ключи сервера

    AG.connect();
}

const AG={


    web_PANEL: async function(panel_name) {
        // load file.html
        const html = await fetch(`panel/${panel_name}.html?`+Math.random()).then(response => response.text());
        dialog(mpers(html,{}),`${panel_name}`, {id:'panel_'+panel_name, width: '90%', height: '90%'});
        await LOADS(`panel/${panel_name}.js?`+Math.random());
        // dialog(html, `Panel ${panel_name}`, {id:'panel_popup', width: '90%', height: '90%'});
        console.log("\n\n\n\n\n");
    },

    // KEYS operations
    get_my_id: async function() {
        let res = await window.pulse.server_request({action:"my_id"});
        return res.my_id;
    },

    get_my_info: async function() {
        let info = await window.pulse.server_request({action:"my_info"});
        AG.my_info = AG.validate_info(info.info);
        for(var user_id in AG.my_info.keys) {
            let [x, ed, name] = AG.my_info.keys[user_id];
            AG.KEYS[1*user_id] = { x: hexU8(x), ed: hexU8(ed), name };
        }
        AG.select_KEYS();
        return info;
    },

    validate_info: function(info) {
        const r = {};
        r.name = info?.name || "Device "+(AG.my_id || "unknown");
        r.comment = info?.comment || "";
        r.owner = info?.owner || "";
        r.location = info?.location || "";
        r.keys = {};
        for(var user_id in info?.keys) {
            if (user_id==AG.my_id || user_id==0) continue;
            let [x, ed, name] = info.keys[user_id];
            if (!name) name = `Device ${user_id}`;
            if( AG.is_key_valid(x) && AG.is_key_valid(ed) ) r.keys[1*user_id] = [x, ed, name];
        }
        return r;
    },

    set_my_info: async function() {
        AG.my_info = AG.validate_info(AG.my_info);
        let res = await window.pulse.server_request({action:"update_my_info", info: AG.my_info});
        if(res!==true) err('update info '+res.error);
        AG.select_KEYS();
    },

    web_INFO: async function() {
        const info = await AG.get_my_info();
        const keys = [];
        for(var id in AG.my_info.keys) {
            let [ x, ed, name ] = AG.my_info.keys[id];
            keys.push({
                id: id,
                key: `${id}-${x}-${ed}`,
                name: name || `Device ${id}`,
            });
        }
        dialog(mpers(DESIGN.info_dialog,{
            keys: keys,
            name: AG.my_info.name,
            comment: AG.my_info.comment,
            owner: AG.my_info.owner,
            location: AG.my_info.location,
            my_id: AG.my_id,
            my_x: U8hex(AG.my_x_public),
            my_ed: U8hex(AG.my_ed_public),
            server_x: U8hex(AG.server_x),
            server_ed: U8hex(AG.server_ed),
            time_reg: info.time_reg || 0,
            time_upd: info.time_upd || 0,
        }),`User Info ${AG.my_id}`, {id:'keys_popup'});

        dom('info_save_button').onclick = async function(ev) {
            ev.preventDefault();
            "name comment owner location".split(" ").forEach(l=>AG.my_info[l]=dom('info_form').elements[l].value);
            await AG.set_my_info();
            clean('keys_popup');
        }

        dom('new_device_button').onclick = async function(ev) {
            ev.preventDefault();
            var s = await my_prompt("Enter key", {header: "New key", placeholder: "02FE-A5EC"});
            let [id, x, ed] = s.split('-');
            let name = `Device`;
            if(ed) { // Add new abonent
                if( !(1*id) || !AG.is_key_valid(x) || !AG.is_key_valid(ed) ) return err("❌ Invalid KEY format");
                name = await my_prompt("Enter name for this key", {header: "Name", placeholder: "The Thing in the pool"});
            } else { // Generate new device
                [x, ed] = s.split('-');
                if(!AG.is_key_valid(x) || !AG.is_key_valid(ed) ) return err("❌ Invalid device KEY format");
                id = await window.pulse.server_request({action:"get_id", x, ed});
                if(!id || !(1*id) || id.error) {                    
                    id = await window.pulse.server_request({action:"create_new_device", x, ed, name});
                    if(!id || !(1*id) || id.error) return err("❌ Error creating new device: " + id.error);
                }
                name = await my_prompt("Enter new name", {header: "Name", placeholder: "The Thing in the pool"});
                pr("✅ New device created, ID: " + id);
            }
            AG.my_info.keys[1*id] = [ x, ed, name ];
            await AG.set_my_info();
            return AG.web_INFO();
        };

/*





            let s = dom('new_device_input').value;




            } else {

            
       



<div>
    <input id="new_device_input" type="text" class="hash_key" value="">
    <button id="new_device_button">Add</button>
  </div>

  <p><h4>Or register new device:</h4>
  <div>
    <div>Keys: <input id="register_device_key" type="text" class="hash_key" value=""></div>
    <div>Name: <input id="register_device_name" type="text" class="hash_key" value=""></div>
    <button id="register_device_button">Register new device</button>
  <div></div>


        const new_device_fn = async function(ev) {
            ev.preventDefault();
            const s = dom('new_device_input').value;
            let [id, X, ed] = s.split('-');
            if( !(1*id) || !AG.is_key_valid(X) || !AG.is_key_valid(ed) ) return err("❌ Invalid KEY format");
            // todo: check existing

            let json = await window.pulse.server_request({action:"get_info", x: X, ed: ed});
            const name = json?.name || `Device ${id}`;

            AG.add_KEY(id, X, ed, name);

            clean('keys_popup');
            AG.web_KEYS();
        };
        dom('new_device_input').onchange = new_device_fn;
        dom('new_device_button').onclick = new_device_fn;

        dom('register_device_button').onclick = async function(ev) {
            ev.preventDefault();
            const keys = dom('register_device_key').value;
            const name = dom('register_device_name').value;
            let [X, ed] = keys.split('-');
            if( !AG.is_key_valid(X) || !AG.is_key_valid(ed) ) return err("❌ Invalid KEY format");
            // todo: check existing
            AG.add_KEY(X, ed);
            clean('keys_popup');
            AG.web_KEYS();
        };
*/
    },



















    // www_CreateNewDevice: async function(s) {
    //     pr("⏳ Generating new device keys...");
    //     try {
    //         let [X,ed] = s.split('-');
    //         if( !AG.is_key_valid(X) || !AG.is_key_valid(ed) ) return err("❌ Wrong key format");
    //         let res = await window.pulse.server_request({"action":"create_new_device", x: X, ed: ed});
    //     } catch (e) {
    //         err("Wrong key "+e);
    //     }
    // },

    // update_server_info: async function(name, data) {
    //     try {
    //         let info = await window.pulse.server_request({"action":"my_info"});
    //         if(info) {
    //             info[name] = data;
    //             let res = await window.pulse.server_request({"action":"update_my_info", "info": info});
    //         }
    //     } catch (e) {
    //         err("Error server:" + e);
    //     }
    // },

    // // Прочесть ключи с сервера
    // server_get_my_keys: async function() {
    //     let info = await window.pulse.server_request({"action":"my_info"});
    //     return info?.keys || {};
    // },

    // // Прочесть ключи с сервера
    // server_set_my_keys: async function() {
    //     let info = await window.pulse.server_request({"action":"my_info"});
    //     return info?.keys || {};
    // },

    // load_KEYS_server: function() {
    //     const s=localStorage.getItem('ws_KEYS_server');
    //     if(!s?.length) return;
    //     let r={}; s.split('\n').forEach( l => {
    //         let [id, X, ed] = l.split('-');
    //         if( AG.is_key_valid(X) && AG.is_key_valid(ed) ) r[1*id] = { X: hexU8(X), ed: hexU8(ed) };
    //     });
    //     AG.KEYS_server = r;
    // },


    select_KEYS: function() {
        const devices = Object.entries(AG.my_info.keys).map(([id, v]) => ({ id: Number(id), name: v[v.length - 1] }));
        dom('devspanel').innerHTML = mpers(DESIGN.devices_panel,{devices});
    },

    www_selectDevice: async function(id) {
        id = 1*id;
        AG.selected_device = id;
        document.querySelectorAll('#devspanel .item').forEach( e => e.classList.remove('selected') );
        document.querySelector(`#Device_${id}`)?.classList.add('selected');
        dom('device_indicator').innerHTML = `🟡 ${id ? AG.my_info.keys[id][2] : "Server"}`;
        // return err("❌such key "+id);
        if(id==0) return;
        var model = await window.pulse.send_secret(0x00, "echo {soft}", id);
        if(!model?.length) {
            console.error("❌ No response for model from "+id, model, typeof model);
            return;
        }
        model = model.trim();
        // pr(`✅ Device ${id} model: ${model}`);
        if( ["default5", "default4", "default3", "default2", "default", "default6ws"].includes(model) ) AG.web_PANEL('INFO');
        // return err("❌ No such key "+id);
    },

    load_KEYS: function() {
        const s=localStorage.getItem('ws_KEYS');
        if(!s?.length) return;
        let r={}; s.split('\n').forEach( l => {
            let [id, x, ed] = l.split('-');
            if( AG.is_key_valid(x) && AG.is_key_valid(ed) ) r[1*id] = { x: hexU8(x), ed: hexU8(ed) };
        });
        AG.KEYS = r;
        AG.select_KEYS();
    },

    save_KEYS: async function() {
        let s=[], serv={}; for(var id in AG.KEYS) {
            s.push(`${id}-${U8hex(AG.KEYS[id].X)}-${U8hex(AG.KEYS[id].ed)}`);
            if(id && id!=AG.my_id) continue; // не сохраняем свои ключи и ключи сервера
            serv[1*id] = { X: U8hex(AG.KEYS[id].X), ed: U8hex(AG.KEYS[id].ed) };
        }
        s=s.join('\n');
        localStorage.setItem('ws_KEYS', s);
        AG.select_KEYS();

        AG.update_server_info('keys', serv);
    },

    add_KEY: async function(id, x, ed, name) {
        id = 1*id;
        if (typeof x === "string") {
            if (!AG.is_key_valid(x)) throw new Error('Invalid x key format');
            x = hexU8(x);
        }
        if (typeof ed === "string") {
            if (!AG.is_key_valid(ed)) throw new Error('Invalid ed key format');
            ed = hexU8(ed);
        }
        AG.KEYS[1*id] = { x: x, ed: ed, name: name || `Device ${id}` };
        await AG.save_KEYS();
    },
    del_KEY: async function(id) {
        delete AG.KEYS[1*id];
        await AG.save_KEYS();
    },
    is_key_valid: function(s) {
        if(s?.length && s.match(/^[0-9A-F]{64}$/)) return true;
        console.log(`❌ Invalid key`, s, typeof s, s?.length);
        return false;
    },

    // WS operations    

    sendTextTo: async function(text) {
        // pr(`⏳ ${text}`);

        text = mpers(text,{
                id: AG.selected_device,
                x: U8hex(AG.KEYS[AG.selected_device].x),
                ed: U8hex(AG.KEYS[AG.selected_device].ed),
                my_x: U8hex(AG.my_x_public),
                my_ed: U8hex(AG.my_ed_public),
                my_id: AG.my_id,
                my_name: AG.my_info.name,
                "\\n": "\n",
        });

        let res;
        try {
            res = await window.pulse.send_secret(0x00, text, 0); // ТУТ ВСЕГДА ТОЛЬКО НА СЕРВЕР AG.selected_device);
        } catch(e) {
            pr("❌ Error: " + e);
            return;
        }               
        // pr(`✅ ${res}`);
        if(typeof res === "object") pr(JSON.stringify(res));
        else pr(res);
    },

    TestData: async function(data) {
        let res;
        data = JSON.stringify(data);
        try {
            res = await window.pulse.send_secret(0x10, data, 0);
        } catch(e) {
            pr("❌ Error sending data: " + e);
            return;
        }               
        pr(`✅ Sent data: [${res}]`);
    },

    // Test: async function(to, action) {

    //     let msg = "TEST";
    //     // if( action ) msg = JSON.stringify({ action: action }); // dom('text').value;

    //     var j = {action: 'update_my_info', info: {
    //         name: "Alice",
    //         email: "alice@example.com",
    //         age: 30
    //     }};

    //     // var j = {action: 'update_my_info', info: "lebedka" };

    //     var j = { action: "my_info" };

    //     if( action ) msg = JSON.stringify(j); // dom('text').value;
    //     pr("⏳ Sending message to "+to+": " + msg);
    //     var res;
    //     try {
    //         res = await window.pulse.send_secret(0x00, msg, to);
    //     } catch(e) {
    //         pr("❌ Error sending message to "+to+": " + e);
    //         return;
    //     }
    //     pr(`✅ Sent message to ${to}: ${msg}\nResponse: ${JSON.stringify(res)}`);
    //     dialog(res, "Response from "+to);
    // },

    KEYS: { },
    my_info: null,
    my_id: null,
    my_x_secret: null,
    my_ed_secret: null,

    // status_url: "http://huly.local:8112/status",

    ws_url: (document.location.host.match('.local')
		? `ws://${document.location.host}:8112/ws/user/v1/`
		: "ws://aguardia.lleo.me:8112/ws/user/v1/"
	),

    ws_bin_message_counter: 0,

    load_keys: function() {

        // AG.load_KEYS(); // прочли базу ключей

        var value = localStorage.getItem('ws_my');
        if (value && value.length) value = value.split('-');

        if( value?.[0] ) AG.my_id = 1*value[0];

        if( !value
            || !(1*value[0])
            || !AG.is_key_valid(value[1])
            || !AG.is_key_valid(value[2])
        ) {
            pr("❌ No keys, generating new ones...");
            value = [0, U8hex(crypto25519.seed()), U8hex(crypto25519.seed())];
        }

        AG.my_seed_x = hexU8(value[1]);
        AG.my_seed_ed = hexU8(value[2]);
        AG.my_x_secret = crypto25519.x_secret(AG.my_seed_x);
        AG.my_x_public = crypto25519.x_public(AG.my_x_secret);
        AG.my_ed_secret = crypto25519.ed_secret(AG.my_seed_ed);
        AG.my_ed_public = crypto25519.ed_public(AG.my_ed_secret);

        value = localStorage.getItem('ws_server');
        if( value && value.length ) {
            value = value.split('-');
            if (AG.is_key_valid(value[0]) && AG.is_key_valid(value[0]) ) {
                AG.server_x = hexU8(value[0]);
                AG.server_ed = hexU8(value[1]);
            }
        }

    },

    ping_device_id: null,
    selected_device: null,
    ping_devices_working: false,
    ping_devices_fn: async function() {
        if(AG.ping_devices_working) return;
        AG.ping_devices_working = true;
        try {
            for(let user_id in AG.my_info.keys) {

                // console.error("Pinging device ", user_id, AG.my_info.keys[user_id]);

                user_id = 1*user_id;
                let e = dom('Device_'+user_id);
                if(user_id==0 || user_id==AG.my_id) continue;

                let x = AG.my_info.keys[user_id][0];
                let ed = AG.my_info.keys[user_id][1];
                window.pulse.send_secret(0x00, JSON.stringify({action: "is_online", user_id: user_id, x: x, ed: ed}), 0)
                // window.pulse.send_secret(0x00, "ping", user_id)
                    .then(res => {
                        console.warn(`Ping response from ${user_id}: `, res, typeof res);
                        e.classList.toggle('disconnect', !res); //  !== "pong")
                        if(user_id === AG.selected_device) {
                            if(res) {
                                dom('device_indicator').innerHTML = `<font color='green'>🟢</font> ${AG.my_info.keys[user_id][2]} ONLINE`;
                                if(AG.onDeviceOnline) AG.onDeviceOnline(user_id);
                            } else {
                                dom('device_indicator').innerHTML = `<font color='red'>🔴</font>${AG.my_info.keys[user_id][2]} OFFLINE`;
                                if(AG.onDeviceOffline) AG.onDeviceOffline(user_id);
                            }
                        }
                    }
                    ).catch(()=>{});
            }
        } catch(e) {}
        AG.ping_devices_working = false;
    },

    connect: async function() {
        const url = this.ws_url + U8hex(AG.my_ed_public);
        window.pulse = new HulypulseClient(url);
        window.pulse.setOnMessage( this.WS_handler_message );
        window.pulse.setOnMessageLogin( this.WS_handler_login );

        window.pulse.setOnConnect( async ()=>{
            console.log("Connected to server");
            dom('status_indicator').innerHTML = `<font color='green'>🟢</font> SERVER CONNECTED ${h(url)}</a>`;
            document.querySelectorAll('.on_server').forEach( e => e.classList.remove('disconnect') );
            // plays("img/pim.mp3");
            // определимся с данными
            if(!AG.KEYS[0]) AG.KEYS[0] = { x: AG.server_x, ed: AG.server_ed, name: "SERVER" };
            if(!AG.KEYS[AG.my_id]) AG.KEYS[AG.my_id] = { x: AG.my_x_public, ed: AG.my_ed_public, name: "MY" };

            if(!AG.my_id) AG.my_id = await AG.get_my_info();
            if(!AG.my_info) {
                await AG.get_my_info();
            }

            AG.ping_devices_working = false;
            if(AG.ping_devices_id) clearInterval( AG.ping_devices_id );
            AG.ping_devices_id = setInterval( AG.ping_devices_fn, 5000);
            AG.ping_devices_fn();

        });
        const ondisconnect_fn = ()=>{
            console.log("Disconnected from server");
            if(AG.ping_devices_id) clearInterval( AG.ping_devices_id );
            dom('status_indicator').innerHTML = `<font color='red'>🔴</font> SERVER DISCONNECTED ${h(url)}`;
            // plays("img/plam.mp3");
            document.querySelectorAll('.on_server').forEach( e => e.classList.add('disconnect') );
        }
        window.pulse.setOnDisconnect( ondisconnect_fn );
        ondisconnect_fn();

        window.pulse.ws_message_counter = 0;
        return window.pulse.wait_connect = window.pulse.connect();
    },

    logout: async function() {
        if( await my_confirm("Are you sure you want to logout?") ) {
            localStorage.removeItem('ws_my');
            pr("✅ Logged out, seeds removed from localStorage. Reload the page.");
        }
    },

    send_signed: async function(s, r) {
        for (let k in r) s += "/"+r[k];
        r.signature = U8hex( crypto25519.sign( stringU8(s), AG.my_ed_secret ) );
        window.pulse.send( JSON.stringify(r) );
    }, 

    WS_handler_login: async function(s) {
            console.log(`Parsing JSON message [${s}]`);
            try {
                var j = JSON.parse(s);
            } catch(e) {
                pr("❌ Invalid JSON message: " + s);
                return;
            }
            const en = 'login_win';

            if(j.action=="login") {
                progress.stop();
                dialog(mpers(DESIGN.login_email_dialog,{}),"Login/SignUp",{id:en});
                let input=dom(en).querySelector('input');
                input.onchange = function(ev) {
                    clean(en)
                    AG.send_signed( j.hash, { type: "email", email: ev.currentTarget.value } );
                    progress.total = 10000; progress.run(0, function(){ err('Error: timeout'); });
                };
                input.focus();
                input.select();
                return;
            }

            if(j.action=="code_sent" || j.action=="code_already_sent") {
                progress.stop();
                dialog(mpers(DESIGN.login_code_dialog,{action:j.action}),"Code from email",{id:en});
                let input=dom(en).querySelector('input');
                input.onchange = function(ev) {
                    clean(en)
                    AG.send_signed( j.hash, { type: "code", code: ev.currentTarget.value, x_public: U8hex(AG.my_x_public) } );
                    progress.total = 3000; progress.run(0, function(){ err('Error: timeout'); });
                };
                input.focus();
                input.select();
                return;
            }

            if(j.action=="login_success") {
                progress.stop();
                // save my keys
                AG.my_id = j.my_id;
                localStorage.setItem('ws_my', AG.my_id+'-'+U8hex(AG.my_seed_x)+'-'+U8hex(AG.my_seed_ed));
                // save server keys
                AG.server_x = hexU8(j.server_X);
                AG.server_ed = hexU8(j.server_ed);
                localStorage.setItem('ws_server', j.server_X + '-' + j.server_ed);
                // success
                pr("✅ Login successful, user_id=" + h(AG.my_id));
                clean('enter_email_dialog_popup');
                window.pulse.close();
                window.pulse.connect();
                return;
            }

            dialog(h(JSON.stringify(j)), "Error");
    },

    // const result = AG.WS_handler_message(addr, bin, key.X);
    WS_handler_message: async function(from, cmd, body) {

        if(cmd==0x00) { // PROTOCOL QUERY
            let text = new TextDecoder().decode(body);
            pr(`✅ 0x00 query from: ${from} [${text}]`);
            return "Hello, world!";
        }

        if(cmd==0x01) { // PROTOCOL ANSWER
            let text = new TextDecoder().decode(body);
            pr(`✅ 0x01 answer from: ${from} [${text}]`);
            return null;
        }

        // if(cmd==0x01) { // SAVE FILE [filename...0x00][data...]
        //     let p = 1; while (p < bin.length && bin[p] !== 0x00) p++;
        //     if (!p || p >= bin.length) return pr("❌ SAVE_FILE: filename error");
        //     let filename = new TextDecoder().decode(bin.slice(1, p));
        //     let filedata = bin.slice(p + 1);
        //     const answer = await AG.SAVE_FILE_handler(filename, filedata);
        //     pulse.send( AG.send(addr, answer) );
        //     return;
        // }

        // if(cmd==0x02) { // READ FILE [filename...0x00][data...]
        //     let p = 1; while (p < bin.length && bin[p] !== 0x00) p++;
        //     if (!p || p >= bin.length) return pr("❌ SAVE_FILE: filename error");
        //     let filename = new TextDecoder().decode(bin.slice(1, p));
        //     let filedata = bin.slice(p + 1);

        //     const answer = await AG.READ_FILE_handler(filename, filedata);
        //     pulse.send( AG.send(addr, answer) );
        //     return;
        // }

        return `❌ Unknown CMD: ${cmd}`;
    },

    MOTO_handler: function(text) {
        pr(`MOTO "${text}`);
        return "MOTO: " + text;
    },

    READ_FILE_handler: async function(filename, filedata) {
        pr(`READ FILE: "${filename}", ${filedata.length} bytes`);
        return `READ_FILE "${filename}", ${filedata.length} bytes`;
    },

    SAVE_FILE_handler: async function(filename, filedata) {
        pr(`SAVE FILE: "${filename}", ${filedata.length} bytes`);
        return `SAVE_FILE "${filename}", ${filedata.length} bytes`;
    },

































    onmessage: async function(raw) {

        // console.log("WS onmessage", raw);
  
        if (typeof raw === "string") {
            if(! window.pulse.ws_bin_message_counter) return AG.WS_handler_login(raw);
            return pr("✅ TEXT message received: " + raw);
        }

        if (raw instanceof Blob) raw = new Uint8Array(await raw.arrayBuffer());
        if (raw instanceof ArrayBuffer || raw instanceof Uint8Array) raw = new Uint8Array(raw);
        else return pr(`❌ Invalid data type "${typeof raw}", use ws.binaryType='arraybuffer';`);

        if (raw.length < 5) return pr("❌ Packet too short");

        let addr = (raw[3] << 24) | (raw[2] << 16) | (raw[1] << 8)  | raw[0];
        let encrypted = raw.slice(4);

        const key = AG.KEYS[addr];
        if(!key) return pr("❌ No keys for addr " + addr);

        let bin = crypto25519.verify_and_decrypt( encrypted, AG.my_x_secret, key.X, key.ed, 5, Math.floor(Date.now() / 1000) );
        if (!bin || !bin.length) {
            return pr("❌ decrypt/verify failed");
        }

        window.pulse.ws_bin_message_counter++;
        if(window.pulse.ws_bin_message_counter > 5) return;

        if (bin.length < 4) return pr("❌ Empty decrypted packet");
        const id = (bin[1] << 8) | bin[0];
        const cmd = bin[2];
        const body = bin.subarray(3);

        AG.WS_handler_message(addr, bin, key.X);
    },

};

// pr("clear"); pr("⏳Init WASM");

window.pr = function(s) {
    if(s=="clear") return output.textContent = "";
    console.log(s);
    output.textContent = s+"\n\n"+output.textContent;
}

window.U8hex = function(u8) {
    if(!(u8?.length)) {
        console.log("U8hex: empty input", typeof u8, u8);
    }
    let o="";
    for (let i = 0; i < u8.length; i++) o += u8[i].toString(16).padStart(2, "0").toUpperCase();
    return o;
}

window.hexU8 = function(hex) { // только для чистого HEХ
    return new Uint8Array( hex.match(/.{1,2}/g).map(byte => parseInt(byte, 16)) );
}

window.stringU8 = function(s) {
    return new TextEncoder().encode(s);
}

window.AG=AG;
main();