GRAF = {
    set: {},

    engine: null,

    ch: async (el, i, action)=>{

        if(!GRAF.set[i]) GRAF.set[i] = { name: '---', code: '', minus: 0, mul: 1, add: 0 };

        if(action=='name') {
            alert('select');

        } else {

            let new_value = await my_prompt(action, {
                header: action,
                default: GRAF.set[i][action],
                enter: 'Submit',
            });
            new_value = 1*new_value;

        }
        GRAF.set[i][action] = new_value;
        if(el) el.innerHTML = h(new_value);
    },

    init: async function() {
        if (this.engine) { clearInterval(GRAF.engine); GRAF.engine = null; }

        /*
        DESIGN.graf_element = `

<div class='a0sel' style='background-color:{#color}'>
    <div>{#value}</div>
    <div class='r'>
        <div>{#code}</div>
        <div>
            -<div class='knz' onclick="GRAF.ch(this,{i},'minus')">{#minus}</div>
            *<div class='knz' onclick="GRAF.ch(this,{i},'mul')">{#mul}</div>
            +<div class='knz' onclick="GRAF.ch(this,{i},'add')">{#add}</div>
        </div>
        <div class='kns' onclick="GRAF.ch(this,{i},'name')">{#name}</div>
    </div>
</div>

<style>
.a0sel { color: black; }
.a0sel .knz, .a0sel .kns {
    color: black;
    display: inline-block;
    width: 30px;
    font-size: 8px;
    background-color: #eee;
    border: 1px solid #ccc;
    border-radius: 4px;
    margin: 0 2px;
    cursor: pointer;
}

.a0sel .kns {
    width: 120px;
}

</style>
        `;

        const brightColors16 = [
  '#FF0000', // red
  '#00A2FF', // blue
  '#00C853', // green
  '#FF6D00', // orange
  '#AA00FF', // purple
  '#00E5FF', // cyan
  '#FFD600', // yellow
  '#D50000', // dark red
  '#2962FF', // deep blue
  '#1B5E20', // deep green
  '#C51162', // magenta
  '#00BFA5', // teal
  '#FF1744', // pink-red
  '#651FFF', // indigo
  '#AEEA00', // lime
  '#FF9100'  // amber
];



        dom('bukas').innerHTML = mpers(DESIGN.graf_element, {
            i:0,
            name:'Red Channel',
            color: brightColors16[0],
            code:'{GRAFMODE0}',
            minus:100,
            mul:200,
            add:300,
            value:'1234'
        });
*/

        if(!AG.selected_device) return err('No selected device for GRAF');       

        if (!window.RGraph) delete window.RGraph;
        await LOADS('js/rg.js?'+Math.random());

        this.RG_init();

        this.engine = setInterval(() => {

            if(!dom('GRAFV0') && GRAF.engine) { clearInterval(GRAF.engine); GRAF.engine = null; return; }
            var query;
            if(GRAF.askmode == 'custom') query = dom('GRAFCODE').value;
            else query=`echo [${dom('GRAFMODE0').value},${dom('GRAFMODE1').value},${dom('GRAFMODE2').value}]`;

            window.pulse.send_secret(0x00, query, AG.selected_device,1000)
                .then((r) => {
                    // console.warn('GRAF data:',r, typeof r);
                    for(let i=0; i<3; i++) {
                        let x = r[i];
                        // console.log('i=',i,'x=',x,typeof x);
                        if(x!==null) {
                            dom('GRAFV'+i).innerHTML = h(x);
                            if(GRAF.askmode != 'custom') {
                                x = 1*x;
                                x -= 1*dom('GRAFMIN'+i).value;
                                x *= 1*dom('GRAFMUL'+i).value;
                                x += 1*dom('GRAFADD'+i).value;
                                // console.log(i,dom('GRAFMIN'+i).value,dom('GRAFMUL'+i).value,dom('GRAFADD'+i).value,x);
                                x=Math.floor(x);
                                dom('GRAFv'+i).innerHTML = h(x);
                            } else {
                                dom('GRAFv'+i).innerHTML = "custom";
                            }
                            x=Math.max(x,0);
                            x=Math.min(x,1023);
                        } else {
                            dom('GRAFV'+i).innerHTML = '';
                            dom('GRAFv'+i).innerHTML = '';
                        }
                        
                        GRAF.line.originalData[i].unshift(x);
                        GRAF.line.originalData[i].pop();
                    }
                    RGraph.SVG.redraw();
                })
                .catch((e) => {
                    GRAF.line.originalData[0].unshift(0);
                    GRAF.line.originalData[0].pop();
                    GRAF.line.originalData[1].unshift(0);
                    GRAF.line.originalData[1].pop();
                    GRAF.line.originalData[2].unshift(0);
                    GRAF.line.originalData[2].pop();
                    RGraph.SVG.redraw();
                    console.error(e);
                });

            // for (let i = 0; i < 3; i++) {
            //     const x = (Math.random() * 1024) | 0;
                
            // }
            // GRAF.line.redraw();
            // RGraph.SVG.redraw();
            // GRAF.line.redrawLines()
        }, 1000);

        dom('panel_GRAF').querySelector('.popup-close').onclick = function() {
            if (GRAF.engine) { clearInterval(GRAF.engine); GRAF.engine = null; }
            if (GRAF.line) { 
                // GRAF.line.clear(GRAF.line.id);
                RGraph.SVG.clear(GRAF.line.id); // GRAF.line = null;
            }
            if (dom('rg')) dom('rg').innerHTML = '';
        };

        var s='';
        [
            { name: '---', code: 'null' },
            { name: 'Hall Sensor', code: '{hall_sensor}' },
            { name: 'Temperature', code: '{temp_sensor}' },
            { name: 'Cycles', code: '{cycles}', mul: 0.000000253, add: -37 }, 
            { name: 'Heap Size', code: '{HeapSize}' },
            { name: 'Free Heap', code: '{FreeHeap}' },
            { name: 'gpio34', code: '{gpioA34}' },
            { name: 'gpio35', code: '{gpioA35}' },
            { name: 'gpio36', code: '{gpioA36}' },

            { name: 'KY-IIC-3V3 Pres', code: '{KY-IIC-3V3_P}' },
            { name: 'KY-IIC-3V3 Temp', code: '{KY-IIC-3V3_T}' },
            { name: 'PH-chaina', code: '{I2C.24:0x26 0xFF}' },
            
        ].forEach((r) => s+=`<option value="${r.code}">${r.name}</option>`);
        dom('GRAFMODE0').innerHTML = s;
        dom('GRAFMODE1').innerHTML = s;
        dom('GRAFMODE2').innerHTML = s;

        dom('GRAFMODE0').value = localStorage.getItem('GRAFMODE0') || 'null';
        dom('GRAFMODE1').value = localStorage.getItem('GRAFMODE1') || 'null';
        dom('GRAFMODE2').value = localStorage.getItem('GRAFMODE2') || 'null';

        dom('GRAFMIN0').value = localStorage.getItem('GRAFMIN0') || '0';
        dom('GRAFMIN1').value = localStorage.getItem('GRAFMIN1') || '0';
        dom('GRAFMIN2').value = localStorage.getItem('GRAFMIN2') || '0';

        dom('GRAFMUL0').value = localStorage.getItem('GRAFMUL0') || '1';
        dom('GRAFMUL1').value = localStorage.getItem('GRAFMUL1') || '1';
        dom('GRAFMUL2').value = localStorage.getItem('GRAFMUL2') || '1';

        dom('GRAFADD0').value = localStorage.getItem('GRAFADD0') || '0';
        dom('GRAFADD1').value = localStorage.getItem('GRAFADD1') || '0';
        dom('GRAFADD2').value = localStorage.getItem('GRAFADD2') || '0';

        dom('GRAFCODE').value = localStorage.getItem('GRAFCODE') || dom('GRAFCODE').placeholder;
    },

    CH_GM: function(n,mode,val){
        if(mode=='MODE') localStorage.setItem('GRAFMODE'+n,val);
        else if(mode=='MIN') localStorage.setItem('GRAFMIN'+n,val);
        else if(mode=='MUL') localStorage.setItem('GRAFMUL'+n,val);
        else if(mode=='ADD') localStorage.setItem('GRAFADD'+n,val);
    },

    line: false,

    RG_init: function() {

        GRAF.line = new RGraph.SVG.Line({id:'rg',
        data:[
            RGraph.SVG.arrayFill({array:[],value:0,length:300}),
            RGraph.SVG.arrayFill({array:[],value:0,length:300}),
            RGraph.SVG.arrayFill({array:[],value:0,length:300}),
            RGraph.SVG.arrayFill({array:[],value:0,length:300})
        ],options: {
        //	gutterLeft:40,
        gutterTop:8,
        gutterBottom:10,
        gutterLeft:40,
        gutterRight:20,

        xaxis: false,
        yaxis: false,

            yaxisMax:1024,
            yaxisMin:0,
            backgroundGridVlinesCount:100,
            backgroundGridHlinesCount:50,
            filled:[false,false,false,false],
            colors:['#c00','#00c','#0c0','#0c8'],
            linewidth:3,
            filledColors:['rgba(255,0,0,0.25)','rgba(0,0,255,0.25)','rgba(0,255,0,0.25)','rgba(0,255,128,0.25)'],
            shadow:true,

            textSize:'8px',
            attribution:false

            }}).draw();
        },


};
GRAF.init();

// alert(1);



/*

var line=false;

LIGHT_FLAG = 0;

function clean(id){ if(idd(id)) setTimeout("var s=idd('"+id+"');if(s)s.parentNode.removeChild(s);",40); }
function idd(id){ return typeof(document.getElementById(id))=='undefined'?false:document.getElementById(id); }
function lidie(s){ var e=idd('buka'); e.innerHTML=e.innerHTML+s; }

function printmas(){ var s0=s1=s2='<p>',p=line.originalData,i; for(i in p[0]) { s0+=p[0][i]+','; s1+=p[1][i]+','; s2+=p[2][i]+','; } lidie('<hr>'+s0+s1+s2+'<hr>'); }

function printmas1(){ if(!line) return; var k50=0,p=line.originalData,i,k=0; for(i in p[0]) { if(++k<=50) k50+=1*p[0][i]; else break; } zabil('datka',Math.floor(k50/50)); } // >

setInterval("printmas1()",500);


function redata(dat,i) { var x,n=GRAFMODE[i];
    if(n=='no') x=false;
    else {
	if(n=='A0') {
		x = dat[0];
		if(LIGHT_FLAG) OBRI(x);
	}
	else if(n=='FLT') x = dat[1] & 0b11111;
	else if(n=='num') x = dat[2];
	else x = ( dat[1] & pinpin[(1*n)] ? 1 : 0 );

	x = Math.min(1024, (x*GRAFMODE_MUL[i] + 1*GRAFMODE_ADD[i]) );
    }

    line.originalData[i].unshift(x);
    line.originalData[i].pop();
}


function AJME(n){ if(!GRAF_ON || STOPALL==1) return;
    LASTAJ=(LASTAJ+n) & (NBUF-1);

    AJAX("/MOTO?MOTO="+encodeURIComponent("echo.buf "+LASTAJ),{
        noajax:1,
        error: function(s){ setTimeout("AJME(0)",500); },
        timeout: 1000,
        ontimeout: function(s){ setTimeout("AJME(0)",500); },
        callback: function(x){
            x=x.replace(/,$/,'');
            if(x=="") return setTimeout("AJME(0)",500);
            var o=JSON.parse("["+x+"]");

            var k=0;
            for(var i in o) {
                redata(o[i],0); redata(o[i],1); redata(o[i],2);
                if(WRITEBUF && ARBUF.length <100000) ARBUF.push(o[i][0]);
            }
            RGraph.SVG.redraw();

            zabil('A0',o[o.length-1][0]);
            zabil('FLT',o[o.length-1][1] & 0b11111);
            zabil('NN',LASTAJ+' / '+o.length);
            for(var u in pinpin) idd('D'+u).className = ( o[o.length-1][1] & pinpin[u] ? 'e_ledgreen' : 'e_ledred' );

            setTimeout("AJME("+o.length+")",500);
        }
    });
}

function bu(e) { AJAX(e.value); }

function polivpinonoff(i) {
    AJ("set poliv.pin = {KEY:Settings.txt poliv.pin}"+"\n"+"if.!empty {poliv.pin} {"+"\n"+"pinmode {poliv.pin} OUTPUT"+"\n"+"pin {poliv.pin} "+i+"\n"+"}");
}

function grafonoff(i) {
    if(i) {
	GRAF_ON = 1;
	STOPALL=0;
	WRITEBUF=0;
	ARBUF=[];
	AJ("MaxA0 = 65535 \n MinA0 = 0 \n set MaxA0.callback =\n set MinA0.callback =\n set FltA0.callback =\n motor-go = 1 \n set.FLT "+getflt()+" \n TIMER.start "+idd('timer_speed').value);
	AJME(0);
	salert('Graf Start',500);
    } else {
	GRAF_ON = 0;
	STOPALL=1;
	WRITEBUF=0;
	ARBUF=[];
	AJ("motor-go = 0\n TIMER.stop \n /MOTOR-OFF");
	salert('Graf Stop',500);
    }
}

function getflt(){
    var x,o=[],p=['FLT_lag','FLT_TOL','FLT_THRESHOLD','FLT_INFLUENCE'];
    for(var i in p) {
	x=idd(p[i]); if(!x) { alert('Error 0: '+p[i]); return ""; }
	x=1*idd(p[i]).value; if(!x) { alert('Error 1: '+p[i]); return ""; }
	o.push(x);
    }
    return o.join(' ');
}

// ==================================================================

STOPALL=0;
WRITEBUF=0;
ARBUF=[];
STOP1=800;
STOP2=800;
HOD1=600;
HOD2=600;


function calibrate(){
	grafonoff(1);
	ARBUF=[];
	STOPALL=1;
	zabil('buka1','');

	line.originalData[0]=Array.from(Array(300), () => 0);
	line.originalData[1]=Array.from(Array(300), () => 0);
	line.originalData[2]=Array.from(Array(300), () => 0);
	RGraph.SVG.redraw();

    var t=0;
    buka('init');
// eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
//AJ("MaxA0 = 65535\nMinA0 = 0\nset MaxA0.callback = \nset MinA0.callback = \nset FltA0.callback = \nmotor-go = 1 \n set.FLT "+getflt()+" \n "+TIMER.start "+idd('timer_speed').value);

    AJ("MinA0 = 0 \n MaxA0 = 1024 \nFltA0 = 0 \n set FLT = "+getflt()+" \n TIMER.start "+idd('timer_speed').value)+" \n set calibrate = 1";
    salert(idd('timer_speed').value,100);

    // salert("1. начать график и запустить двигатель",1000);
    t+=1; setTimeout("buka('1.0: график'); STOPALL=0; AJME(0); AJ('/MOTOR-LL');" , t*1000);

    // salert("2. через 5 сек начать запись на 2 секунды, затем запустить двигатель в другую сторону",1000);
    t+=3; setTimeout(startsave,t*1000); t+=2; setTimeout("calcu(1);AJ('/MOTOR-RR');",t*1000);

    // salert("3. через 2 сек (пусть раскрутится) начать запись на 2 секунды",1000);
    t+=2; setTimeout(startsave,t*1000); t+=2; setTimeout("calcu(2)",t*1000);

    // salert("4. через 5 сек (пусть снова упрется) начать запись на 2 сек и запустить двигатель обратно",1000);
    t+=3; setTimeout(startsave,t*1000); t+=2; setTimeout("calcu(3);AJ('/MOTOR-LL');",t*1000);

    // salert("5. через 2 сек начать запись на 2 секунды",1000);
    t+=2; setTimeout(startsave,t*1000); t+=2; setTimeout("calcu(4)",t*1000);

    // salert("6. через 1 секунду отключить мотор и график",1000);
    t+=1; setTimeout(function(){
        buka('STOP');
        STOPALL=1;
        AJ("set MOTOROUT = 7 \n /MOTOR-STOP \n TIMER.stop \n set calibrate = 0");
        calcurez();
    },t*1000);
}

function buka(s){ zabil('buka1',vzyal('buka1')+'<br>'+s); }

function startsave() { ARBUF=[]; WRITEBUF=1; }

calcudoc=[];

function cpr(P) { o=''; for(var i=0;i<P[3].length;i++) {
    var c=P[3][i];
    if(c==P[2]) c='<font color=red>'+c+'</font>';
    else if(c==P[1]) c='<font color=blue>'+c+'</font>';
    o+=c+' ';
    }
    return o;
}

function calcurez(q){ alert('calcurez');
    o='<p>Заедания:';
    o+='<br>1: '+calcudoc[1][0]+' ('+calcudoc[1][1]+'...'+calcudoc[1][2]+') :'+cpr(calcudoc[1]);
    o+='<br>3: '+calcudoc[3][0]+' ('+calcudoc[3][1]+'...'+calcudoc[3][2]+') :'+cpr(calcudoc[3]);
    o+='<p>Прогоны:';
    o+='<br>2: '+calcudoc[2][0]+' ('+calcudoc[2][1]+'...'+calcudoc[2][2]+') :'+cpr(calcudoc[2]);
    o+='<br>4: '+calcudoc[4][0]+' ('+calcudoc[4][1]+'...'+calcudoc[4][2]+') :'+cpr(calcudoc[4]);

    // var M2=Math.min( calcudoc[1][1] , calcudoc[3][1] );
    var M2=Math.min( calcudoc[1][0] , calcudoc[3][0] );
    var M1=Math.max( calcudoc[2][2] , calcudoc[4][2] );

    if(M1 > M2) o+="<br><b><font color=red>калибровка не удалась: "+M1+" > "+M2+"</font><b>";
    else {
	    var rec=Math.floor( M1+ (M2-M1)*2/3  );
            o+='<p><b>Рекомендуемый порог между '+M1+' и '+M2+' = '+rec+". Данные записаны в файл /CALIBR</b>";
            AJ("A0.MAX = "+rec+" \n FILE.save { /CALIBR MinA0 0\nMaxA0 "+rec+"\nFLT "+getflt()+" }",function(x){if(x=='OK') salert("Saved: /CALIBR"); });
    }
    buka(o);
}

function calcu(q){
        WRITEBUF=0,o='',k=0,min=999999999,max=0;
        for(var i=0;i<ARBUF.length;i++) { var c=ARBUF[i]; k+=c; o+=c+' '; if(max<c)max=c; if(min>c) min=c;  }
        var m=Math.floor(k/ARBUF.length);
        buka('<br>'+o+'<br>итого замеров: '+ARBUF.length+'<br><b>средняя величина: '+m+' (от '+min+' до '+max+')</b><hr>');
        calcudoc[q]=[m,min,max,ARBUF];
        return m;
}

function CH_GM(n,mode,val){
        if(mode=='MODE') GRAFMODE[n]=val;
    else if(mode=='MUL') GRAFMODE_MUL[n]=val;
    else if(mode=='ADD') GRAFMODE_ADD[n]=val;
    else return;
    f5_save('a0_'+mode+'_'+n,val);
}

function CH_setup(){
    for(var n=0;n<3;n++) { //>
	var x=f5_read('a0_MODE_'+n); if(!x && x!==0) x=(n?'---':'A0'); idd('GRAFMODE'+n).value=x;
	var x=f5_read('a0_MUL_'+n);  if(!x && x!==0) x=(n?100:0); idd('GRAFMUL'+n).value=x;
	var x=f5_read('a0_ADD_'+n);  if(!x && x!==0) x=50+300*n; idd('GRAFADD'+n).value=x;
    }
}

*/