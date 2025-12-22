ESP = {
    my: {},

    sensor: async ()=> {

        dialog(`
<div class="sensors" id='my_sensors' style='min-width:300px;'></div>

<style>
.sensors {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
  gap: 12px;
}

.sensor {
  display: grid;
  grid-template-rows: auto 1fr auto;
  align-items: center;
  padding: 8px;
  border: 1px solid #2a2a3a;
  border-radius: 10px;
  background: #1b1b28;
  color: #e6e6f0;
  text-align: center;
}

.sensor-title {
  font-size: 12px;
  opacity: 0.8;
  margin-bottom: 4px;
  word-break: break-all;
}

.sensor-icon {
  width: 64px;
  height: 64px;
  margin: 0 auto;
  border-radius: 8px;
  background: #2b2b40;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 32px;
}

.sensor-proto {
  font-size: 11px;
  margin-top: 6px;
  opacity: 0.7;
}
</style>

`,`My Sensors`,{width:'80vw', height:'60vh',style:"background-color:#739ec4;color:white;"}); 


const tmpl = `
  <div class="sensor">
    <div class="sensor-title">{#name}</div>
    <img src="{#icon}" class="sensor-icon">
    <div class="sensor-proto">{#protocol}</div>
  </div>`;

        var res = await window.pulse.send_secret(0x00, "ONEWIRE.begin 26\necho {ONEWIRE.SCAN}", AG.selected_device, 30000);
        if(res?.length) {
            console.log('1-Wire Sensors', res);

            res.split(',').forEach( line => {
                var name = line.trim();
                if(name=='') return;
                var r={protocol: '1-Wire'};
                if(name.endsWith('_DS18B20')) {
                    r.name = name.replace('_DS18B20','').split(':')[1];
                    r.icon = "panel/img/Sensor_DS18B20.webp";
                }
                else {
                    r.name = name;
                    r.icon = "panel/img/Sensor_DS18B20.webp";
                }
                if(r.name) dom('my_sensors').innerHTML = dom('my_sensors').innerHTML + mpers(tmpl, r);
            });

        }

        res = await window.pulse.send_secret(0x00, "I2C.begin 21 22 100000 50\necho {I2C.SCAN}", AG.selected_device, 30000);
        if(res?.length) {
            console.log('I2C Sensors', res);

            res.split(',').forEach( line => {
                var name = line.trim();
                if(name=='') return;
                var r={protocol: 'I2C'};

                if(name=='0x78') {
                    r.name = 'KY-IIC-3V3';
                    r.icon = "panel/img/Sensor_KY-IIC-3V3.webp";
                }
                else {
                    r.icon = "panel/img/Sensor_I2C.webp";
                    r.name = name;
                }

                if(r.name) dom('my_sensors').innerHTML = dom('my_sensors').innerHTML + mpers(tmpl, r);
            });
        }

        res = await window.pulse.send_secret(0x00, `
a34 = 0
a35 = 0
a36 = 0
repeat 10 {
    a34 += {gpioA34}
    delay 10
    a35 += {gpioA35}
    delay 10
    a36 += {gpioA36}
    delay 10
}
a34 /= 10
a35 /= 10
a36 /= 10
echo {"A34": {a34}, "A35": {a35}, "A36": {a36}}
            `, AG.selected_device, 30000);
        console.log('ADC Sensors', res);
        for(var i in res) {
            if(res[i]*1 < 20) continue;
            dom('my_sensors').innerHTML = dom('my_sensors').innerHTML + mpers(tmpl,{
                protocol: 'ADC',
                name: `ADC${i}`,
                icon: 'panel/img/Sensor_ADC.webp'
            });
        }

    },

    gpio: async (mode)=> {

        const html = `
<center><div id='menuesp'></div></center>

<p><center><div id='karta' style='width:1px;height:1px;display:block;position:relative;align:left;padding:0;magrin:0;text-align:left;'></div></center>

<center><table><td><tt>
<div><div class='cY in' id='X_in'>&#128242;</div> - <span id='Y_in'>pinmode (pin) INPUT</span></div>
<div><div class='cY in' id='X_1'><span style='color:green;font-weight:bold'>1</span></div> - <span id='Y_1'>pinmode (pin) OUTPUT ; pin (pin) 1</span></div>
<div><div class='cY in' id='X_0'><span style='color:red;font-weight:bold'>0</span></div> - <span id='Y_0'>pinmode (pin) OUTPUT ; pin (pin) 0</span></div>
<div><div class='cY in' id='X_tone'>&#127925;</div> - <span id='Y_tone'>pinmode (pin) OUTPUT ; tone (pin) 440</span></div>
<div><div class='cY in' id='X_pwm'>&#128246;</div> - <span id='Y_pwm'>pinmode (pin) OUTPUT ; pwm (pin) 600</span></div>
</tt></td></table></center>

<center><table id='tabesptext'><td><pre id='esptext' class='br' style='white-space:pre-wrap'></pre></td></table></center>

<style>

.zml,.cY {
    margin:1px;
    padding:4px;
    background-color:white;
    border-radius:100%;
    border:1px solid#ccc;
    font-size: 15px;
    width: 15px;
    text-align: center;
    height: 15px;
}
.zml { position:absolute; z-index:120; }

.Disp {
  padding:10px 20px 10px 20px;
  margin:10px 20px 10px 20px;
  text-align:center;
  position:absolute;
  width:100px;
  height:150px;
  top:-100px;
  font-size:100px;
  display: inline;
  vertical-align: bottom;
  z-index: 5;
  background-color: white;
}

.Disp DIV { position:absolute; bottom:15px; width: 100px; text-align: center; font-size:20px; font-weight:bold; }

</style>
`;
            dialog(html, 'ESP GPIO Map', { id: 'gpio_dialog', width: '95vw', height: '90vh' });

/*
function grice(x,y){ LINX+=x; LINY+=y;
    idd('gpio').style.top=LINY+'px'; idd('gpio').style.left=LINX+'px';
    zabil('buka',"'gpio':["+LINY+","+LINX+"],");
}

// <i style='position:absolute;z-index:120;top:10px;left:10px;' id='gpio' class=e_ledyellow></i>

<p><input type=button value="|" onclick="grice(0,-1)"> <input type=button value="||" onclick="grice(0,-10)">

<p><input type=button value="<==" onclick="grice(-10,0)"> <input type=button value="<--" onclick="grice(-1,0)">
      <input type=button value="OK" onclick="zabil('buka2',vzyal('buka2')+vzyal('buka'))">
      <input type=button value="-->" onclick="grice(+1,0)"> <input type=button value="==>" onclick="grice(+10,0)">
<p><input type=button value="|" onclick="grice(0,+1)"> <input type=button value="||" onclick="grice(0,+10)">
<p><div id=buka></div>
<p><div id=buka2></div>
</center>
*/


// LINX=0; LINY=0;

const esp_about = {
    ESP32: `
<p><a href='https://diytech.ru/projects/spravochnik-po-raspinovke-esp32-kakie-vyvody-gpio-sleduet-ispolzovat'>link</a>
<dd>0 - не соединять с землей, иначе BOOT! outPWM
<dd>1 TX
<dd>2 LED?
<dd>3 RX
<dd>4 13 16 17 18 19 21 22 23 24 25 26 27 32 33 - OK
<dd>12 - не подтягивать вверх, иначе не грузится!
<dd>5 14 15 outPWM
<dd>34 35 36 39 - input only!
<p>Ёмкостные: 0 2 4 12 13 14 15 27 32 33
<p>АЦП 18 бит: 0 2 12 13 14 15 25 26 27 32 33 34 35 36 37 38
<p>ЦАП: 25 26
<p>допустимый ток 40 Ма
`,

ESP8266: `
<p>ESP8266 имеет 15 полноценных GPIO выходов, 6 из которых заняты микросхемой flash памяти.
<br>GPIO 0,1,2,3,15 имеют ограничения при использовании: - не рекомендуется их использовать для сухого контакта, кнопок и прерываний:
<dd>GPIO 0 (FLASH), 2 (LED) - не должны быть подтянуты к минусу при старте модуля.
<dd>GPIO 15 - в момент старта должен подтянут к минусу через резистор 10к.
<dd>GPIO 1 - TXD, 3 - RXD
<br>GPIO16 - только на OUTPUT (или для пробуждения, если подключить к RESET)
<br>
<p>Рекомендуемые для NFC-читалки:
<br>RST     = GPIO5
<br>SDA(SS) = GPIO4
<br>MOSI    = GPIO13
<br>MISO    = GPIO12
<br>SCK     = GPIO14
<br>
<p>В моем фреймворке рекомендуется:
<br>2 - led и подключение лампочек, все равно лампа
<br>3 - звук, все равно RX пропадает, а так прошивку тоже слышно
`,
};

const places={

        esp12: {
            w:464,
            h:466,
            text: esp_about.ESP8266,
            name:'ESP-12',
            file:'panel/img/esp-esp12.webp',
            'gpio15':[158,97],
            'gpio2':[185,97],
            'gpio0':[210,97],
            'gpio4':[236,97],
            'gpio5':[261,97],
            'gpio3':[287,97],
            'gpio1':[313,97],
            'gpio13':[160,351],
            'gpio12':[186,351],
            'gpio14':[211,351],
            'gpio16':[237,351],
            'gpioA0':[288,351]
        },

        node: {
            w: 981,
            h: 625,
            text: esp_about.ESP8266, 
            name:'Node MCU',
            file:'panel/img/esp-node.webp',
            'gpioA0': [117,275],
            // 'gpio10':[194,275],
            // 'gpio9':[226,275],
            'gpio16':[98,603],
            'gpio5':[126,603],
            'gpio4':[152,603],
            'gpio0':[180,603],
            'gpio2':[209,603],
            'gpio14':[289,603],
            'gpio12':[315,603],
            'gpio13':[343,603],
            'gpio15':[369,603],
            'gpio3':[396,603],
            'gpio1':[421,603]
        },

        d1mini: {
            w:865,
            h:500,
            text:esp_about.ESP8266,
            name:'D1 mini',
            file:'panel/img/esp-d1mini.webp',
            'gpioA0':[138,212],
            'gpio16':[176,212],
            'gpio14':[213,212],
            'gpio12':[249,212],
            'gpio13':[284,212],
            'gpio15':[321,212],
            'gpio1':[101,625],
            'gpio3':[138,625],
            'gpio5':[176,625],
            'gpio4':[213,625],
            'gpio0':[249,625],
            'gpio2':[286,625]
        },

        'ESP-WROOM-32': {
            w:1401,
            h:715,
            dy:-8,
            dx:-7,
            text: esp_about.ESP32,
            name:'ESP-WROOM-32',
            file:'panel/img/ESP-WROOM-32.webp',
            // func: function(){
            //     let o="<div class='Disp' style='left:0px'>&#127777;<div><TT id='temp_sensor'></TT>&#176;C</div></div>";
            //     o+="<div class='Disp' style='left:140px'>&#129522; <div id='hall_sensor'></div></div>";
            //     // &#128225; &#128752; &#128251;
            //     dom('karta',dom('karta')+o);
            // },
            // func1s: function(){
            //     AJ("echo temp_sensor={temp_sensor}@@@hall_sensor={hall_sensor}",function(s){ // salert(s,2000);
            //     s=s.split('@@@'); for(var i in s) {	var l=s[i].split('='); if(idd(c(l[0]))) zabil(c(l[0]),c(l[1])); }
            //     });
            // },
            //'GND   ':[164,498],
            //'3.3   ':[190,498],
            //'___   ':[218,498],
            'gpio36':[245-1,498],
            'gpio39':[272-1,498],
            'gpio34':[299-1,498],
            'gpio35':[326-2,498],
            'gpio32':[353-2,498],
            'gpio33':[380-3,498],
            'gpio25':[407-3,498],
            'gpio26':[434-3,498],
            'gpio27':[461-4,498],
            'gpio14':[488-5,498],
            'gpio12':[515-5,498],
            //'GND'   :[548,564],
            'gpio13':[548,594],
            ///'gpio9' :[548,623],
            ///'gpio10':[548,653],
            ///'gpio11':[548,682],
            ///'gpio6' :[548,711],
            ///'gpio7' :[548,741],
            ///'gpio8' :[548,771],
            'gpio15':[548,800],
            'gpio2' :[548,830],
            //' GND  ':[164,898-2],
            'gpio23':[190,898-2],
            'gpio22':[219,898-2],
            'gpio1' :[245-1,898-2],
            'gpio3' :[272-1,898-2],
            'gpio21':[299-1,898-2],
            //' NC ':[326-2,898-2],
            'gpio19':[353-2,898-2],
            'gpio18':[380-3,898-2],
            'gpio5' :[407-3,898-2],
            'gpio17':[434-3,898-2],
            'gpio16':[461-4,898-2],
            'gpio4' :[488-5,898-2],
            'gpio0' :[515-5,898-2]
        },
    };

    var o="<option value=''>---</option>";
    for(var i in places) o+=`<option value='${i}'>${places[i].name}</option>`;
    dom('menuesp',`<select id='typesys' onchange="if(this.value!=''&&this.value!='${mode}')ESP.gpio(this.value)">${o}</select>`);

    if(!mode) {
        mode=localStorage.getItem('ESP_select');
    } else {
        localStorage.setItem('ESP_select',mode);
    }
    if(mode) {
        dom('typesys').value=mode;
        var m=places[mode];
        dom('esptext',m.text);
        dom('tabesptext').width=Math.min(650,getWinW()*0.9);
        var o=`<img id='kartaimg' src='${m.file}' onerror="this.src=this.src.replace(/^.+(\/[^\/]+)$/g,'$1')">`;
        dom('karta').style.width=m.w+'px';
        dom('karta').style.height=m.h+'px';
        var ls=dom('X_in').innerHTML;
        for(var i in m) if(i.indexOf('gpio')==0) {
            var y=m[i][0]-4,x=m[i][1]-4;
            if(m.dx) x+=m.dx;
            if(m.dy) y+=m.dy;
            o+=`<div title='${i}' style='top:${y}px;left:${x}px;' id='${i}' class='zml mv us in' onclick='ESP.chgpio(this)'>${ls}</div>`;
        }
        dom('karta',o);
        if(m.func) m.func();
    }

    // setInterval(function(){ if(LAST_L && mesta[LAST_L] && mesta[LAST_L].func1s) mesta[LAST_L].func1s(); },1000);
    },

    chgpio: async (e) => {
        var q,s,pin=e.id.replace(/^gpio/,''),c=e.innerHTML;
        if(c==dom('X_in').innerHTML) q='1';
        else if(c==dom('X_1').innerHTML) q='0';
        else if(c==dom('X_0').innerHTML) q='tone';
        else if(c==dom('X_tone').innerHTML) q='pwm';
        else if(c==dom('X_pwm').innerHTML) q='in';
        else return alert('error');
        s=dom('Y_'+q).innerHTML.replace(/\(pin\)/g,pin).replace(/\s*\;\s*/g,'\n');
        // salert(s,500);
        e.innerHTML=dom('X_'+q).innerHTML;
        console.log(s);
        progress.run(0, function(){ err("Error"); });
        await window.pulse.send_secret(0x00, s, AG.selected_device);
        progress.stop();
    },

    monitor: async ()=> {
        AG.web_PANEL('GRAF');
    },

    execute: async (cmd) => {
        if(!cmd || cmd.trim()=='') return;
        localStorage.setItem('LastConsole', cmd);
        progress.run(0, function(){ err("Error"); });
        const res = await window.pulse.send_secret(0x00, cmd, AG.selected_device, null, 20000);
        progress.stop();
        const el = dom('tarea_res');
        // el.innerHTML = h(res) + '\n' + el.innerHTML;
        el.innerHTML += '\n' + h(res);
        el.scrollTop = el.scrollHeight;
    },

    info: async()=> {
        progress.run(0, function(){});
        const tmpl = await fetch(`panel/info.tmpl`).then(response => response.text());
        const res = await window.pulse.send_secret(0x00, tmpl, AG.selected_device);
        console.log('System Info', res);
        const info = {};
        var s='';
        res.split('\n').forEach( line => {
            if(line.trim()=='') return;
            if(line.trim().substring(0,1)=='#') return;
            if(line.indexOf('[')>=0) {
                s += `<div><h5>${h(line.replace(/[\[\]]/g,'').trim())}</h5></div>`;
                return;
            }
            s += `<div><b>${h(line.split('=')[0].trim())}:</b> ${h(line.split('=').slice(1).join('=').trim())}</div>`;
        });
        progress.stop();
        dialog(s, 'System Info');
    },

    restart: async ()=> {
        if(!(await my_confirm("Reboot device?"))) return;
        progress.run(0, function(){ err("Error"); });
        window.pulse.send_secret(0x00, "WS.stop\nESP.restart", AG.selected_device);
        AG.onDeviceOnline = null;
        setTimeout( async ()=>{
            AG.onDeviceOnline = (device_id) => { progress.stop(); };
        }, 500);
    },

    wifi: async ()=> {
        progress.run(0, function(){});
        var res = await window.pulse.send_secret(0x00, "echo {WIFI.scan}", AG.selected_device, null, 30000);
        progress.stop();

        console.log('WiFi Scan', res);
        var s='';

        ESP.my.channels=[]; for(var i=1;i<=13;i++) ESP.my.channels.push({n:i,power:0});
        ESP.my.networks=[];
        res.split('\n').forEach( line => {
            if(line.trim()=='') return;
            let [
                secured,   // 0/1
                channel,   // 1–13
                unknown,   // всегда 1, можно забить
                rssi,      // dBm, отрицательное
                quality,   // %
                mac,     // MAC
                ...ssid    // имя сети
                ] = line.split(' ');
                ssid = ssid.join(' ');
            ESP.my.networks.push({ secured, channel, quality, ssid, quality2: quality/2, mac });
            console.log('Network:', secured, ssid, typeof secured );
            let r = ESP.my.channels.find(c => c.n == 1*channel);
            r.power += 1*quality;
        });
        ESP.my.networks.sort( (a,b) => b.quality - a.quality );

        

        // var o=''; for(var i=0;i<11;i++) o+="<div class='br'>"+(i+1)+" <div class='in' style='width:"+(channels[i])+"px;height:20px;background-color:green'></div></div>";
        dialog(mpers(`
<table style='border:none;width:100%;border-collapse:collapse;'>
<tr style='vertical-align:top;'>
<td>
<h4>Networks</h4>
<table style='border:none;border-collapse:collapse;'>
    {for(networks):
    <tr>
        <td>
            {case(secured):
                {1:&#128274;}
                {0:&#128275;}
            }
        </td>
        <td>{00.:channel}</td>
        <td>
        <div style="display:flex;align-items:center;gap:4px">
            <div style="width:{quality2}px;height:10px;background:red"></div>
            <span style="font-size:8px">{#quality}%</span>
        </div>
        </td>
        <td><div style='cursor:pointer;' onclick='ESP.WIFIconnect(this)'>
        {case(ssid):
            {:<font color="#CCCCCC">{#mac}</font>}
            {*:{#ssid}}
        }
        </div></td>
    </tr>
    }
</table>

</td><td style='width:20px;'></td>
<td>
<h4>Channels</h4>
    {for(channels):
        <div class='br'>{00.:n} <div class='in' style='width:{#power}px;height:8px;background-color:green'></div></div>
    }
</td>
</tr></table>
        `,{
            networks: ESP.my.networks,
            channels: ESP.my.channels
        }));
    },

    WIFIconnect: async (e) => {
        const ssid = e.textContent.trim();
        if(!ssid || ssid.trim()=='') return;
        let r = ESP.my.networks.find(c => c.ssid == ssid || c.mac == ssid);

        if(r.secured=='1') {
            var password = await my_prompt(`Рassword for "${h(ssid)}":`, 'WiFi Password');
        } else {
            var password = '';
            if(!(await my_confirm(`Connect to "${h(ssid)}"?`))) return;
        }

        progress.run(0, function(){ err("Error"); });
        const res = await window.pulse.send_secret(0x00, `
echo ПОТОМ РАЗБЕРУСЬ
exit
WIFI.disconnect YES
WIFI.APdisconnect YES
usleep 500

WIFI.autoconnect YES
WIFI.autoreconnect YES
WIFI.persistent FALSE
WIFI.mode STA\n\
WIFI.dns NO\n\
\n\
WIFI "+net+" "+pass+"\n\
WIFI.waitconnect\n\
\n\
if.!WIFI {\n\
    echo ERROR\n\
    exit\n\
}\n\
\n\
echo SUCCESS\\nhttp://{ip}\\nhttp://{mdns}.local\n\
playip\n\
\n\
FILE.save.text /wifi_last.txt "+net+"\\n"+pass+"\n\
\n\
            WIFI.connect "${ssid.trim()}" "${password.trim()}"`, AG.selected_device, null, 20000);
        progress.stop();
    },

    fileman: async ()=> {
        progress.run(0, function(){ err("Error"); });
        const res = await window.pulse.send_secret(0x00, "echo {dir}<===>{FILE:/stoplist.txt}", AG.selected_device);
        progress.stop();
        if(typeof res != 'string' || res=='') return err("no files");
        const filelist = res.split("<===>")[0].split("\n");
        const stoplist = res.split("<===>")[1].split("\n");
        console.log('Fileman', filelist, stoplist);

        const stop = new Set(
        stoplist
            .map(s => s.trim())
            .filter(s => s && !s.startsWith('#'))
            .map(s => s.replace(/^\/+/, ''))
        );

        const files = filelist
        .map(s => s.trim())
        .filter(s => s)
        .map(s => {
            const [size, ...rest] = s.split(' ');
            const name = rest.join(' ').trim().replace(/^\/+/, '');
            return {
            name,
            size: +size,
            stop: stop.has(name) ? 1 : 0
            };
        })
        .sort((a, b) => a.name.localeCompare(b.name));

        dialog(mpers(`
<table border=0 id='filetab' style='width:100%;border-collapse:collapse;'>
{for(files):
    <tr id="file_{#name}">
        <td onclick='ESP.file_del(this)' class='mv'>&#10060; &#160; </td>
        <td style='cursor:pointer;color:blue;' onclick='ESP.file_editor(this)'>{#name}</td>
        <td> &#160; &#160; </td>
        <td alt='Change dostup' onclick='ESP.ch_stop(this)' class='mv us'>{case(stop):
{1:&#128274;}
{0:&nbsp;}
        }</td>
        <td style='font-size:8px;'><span name="size">{#size}</span> bytes</td>
    </tr>
}
</table>

<div><span class='ll' onclick="ESP.file_editor()">Create New</span></div>
        `, { files }), "Files");
    },

    file_editor: async (e) => {
        let file = '';
        let content = '';
        let new_file = false;
        if(!e) {
            file = await my_prompt("File name:", "New File");
            if(!file || file.trim()=='') return;
            new_file = true;
        } else {
            const tr = e.closest('tr');
            file = tr.id.replace('file_','');
            const ext = file.split('.').pop().trim().toLowerCase();
            console.log('Edit file', file, 'ext', ext, ext.length);
            if (['jpg','jpeg','png','gif','ico','svg','bmp','webp'].includes(ext)) return;
            if (['mp3','ogg'].includes(ext)) return;
        }

        dialog(mpers(`<div><b>${file}</b> &nbsp; <span onclick="ESP.filedel()\">&#128274;</span></div>

<textarea id="edit_content" style="
    width:90vw;
    height:70vh;
    margin:0;
    padding:0;
    box-sizing:border-box;
">{#content}</textarea>

<br><input type='button' value='Save' onclick="ESP.savefile('{#file}',dom('edit_content').value)">
</form>`,{
    file: file,
    content: content
}), `Edit File: ${h(file)}`,{
    id:'file_edit_dialog',
    style: 'background-color:#f0f0f0;',
});

    if(new_file) return;

    progress.run(0, function(){ err("Error"); });
    content = await window.pulse.send_secret(0x04, `/${file}`, AG.selected_device);
    dom('edit_content').value = content;
    progress.stop();


},

    savefile: async (file, content) => {
        content=content.replace(/\r/g,''); // вот это не люблю
        progress.run(0, function(){ err("Error"); });
        const res = await window.pulse.send_secret(0x03, `/${file}\n${content}`, AG.selected_device);
        progress.stop();
        if(res.trim() != 'OK') return err(`Error saving file: ${h(res)}`);
        clean('file_edit_dialog');
    }
    

    /*
  <div class="rth" onclick='ESP.restart()' >&#128244;<span>Reboot</span></div>
  <div class="rth" onclick='ESP.wifi()'    >&#128246;<span>WiFi</span></div>
  <div class="rth" onclick="ESP.getsofts()">&#128693;<span>Update</span></div>
  <div class="rth" onclick='ESP.gpio()'    >&#127981;<span>GPIO</span></div>
  <div class="rth" onclick='ESP.monitor()' >&#127748;<span>Monitor</span></div>
  <div class="rth" onclick='ESP.fileman()' >&#128190;<span>Files</span></div>
*/
},

INFO = {
    init: async ()=>{
        await LOADS('panel/sys.css?'+Math.random());
        const el = dom('panel_INFO');
        el.style.width = '90%';
        el.style.height = '90%';
        el.style.margin = 'auto';

        dom("tarea").value = localStorage.getItem('LastConsole') || '';

        window.pulse.send_secret(0x00, `echo {ESP_TYPE} v{VER} "{VERNAME}" http://{ip}`, AG.selected_device).then( res => {
            dom('ESPTYPE').innerHTML = h(res);
        }).catch( e => {
            dom('ESPTYPE').innerHTML = h(e.message);
        });

    },
};

INFO.init();
