// умная подгрузка
// первый аргумент - имя файлы js или css или массив ['1.js','2.js','1.css']
// второй необязательный аргумент - функция, запускаемая по окончании удачной загрузки ВСЕХ перечисленных
// третий необязательный - функция при ошибке каждого из
// четвертый (sync) устаналивать в true, если важен порядок загрузки
// LOADS('1.js',function(){Удачно});
// LOADS(['1.js','2.css'],function(){ SUCCESS!},function(){ERROR!},sync);
// с ожиданием: await LOADS_promice(['1.js','2.css'],sync); // start end loaded
const LOADES={};
function LOADS(urls, onSuccess, onError, sync) {
    if(typeof urls === 'string') urls = [urls];
    urls = urls.filter(url => !LOADES[url]); // Отфильтруем уже загруженные
    if(!urls.length) return onSuccess ? onSuccess() : true; // Если нечего загружать, сразу успех
    const urls2 = [...urls];
    urls.forEach(url => {
        const attr = /\.css($|\?.+?$)/.test(url)
            ? { elname:'link', href:url, type:'text/css', rel:'stylesheet', media:'screen'}
            : { elname:'script', src:url, type:'text/javascript', defer: true};
        const el = document.createElement(attr.elname);
        for(const [a,b] of Object.entries(attr)) el.setAttribute(a,b);
        if(sync) el.async = false; // Управляем асинхронностью для скриптов
        el.onerror = (e) => {
            onError ? onError(url,e) : console.error(`Failed to load: ${url}`);
        };
        el.onload = () => {
            LOADES[url] = 1;
            urls2.splice(urls2.indexOf(url),1);
            if(!urls2.length) { ajaxoff(); if(onSuccess) onSuccess(); }
        };
        document.head.appendChild(el);
    });
    ajaxon();
}
LOADS_sync=function(urls,onSuccess,onError) { LOADS(urls,onSuccess,onError,1) }
LOADS_promise=LOADS_promice=include=function(urls,sync) { return new Promise(function(resolve,reject){ LOADS(urls,resolve,reject,sync) }); };

function getScrollH() { return window.pageYOffset; }
function getScrollW() { return window.pageXOffset; }
function getWinW() { return window.innerWidth; }
function getWinH() { return window.innerHeight; }
function getDocH() { return document.documentElement.scrollHeight; }
function getDocW() { return document.documentElement.scrollWidth; }

// =========================================================================

function f5_save(key, value, storage) {
    try { window[storage?'sessionStorage':'localStorage'].setItem(key, value); return true; }
    catch(er) { console.error(er); return false; }
}

function f5_read(key, def, storage) {
    try { const val = window[storage?'sessionStorage':'localStorage'].getItem(key); return (val === null ? def : val); }
    catch(er) { console.error(er); return false; }
}

function f5_del(key, storage) {
    try { window[storage?'sessionStorage':'localStorage'].removeItem(key); return true; }
    catch(er) { console.error(er); return false; }
}

function f5_all(storage) {
  const items = {}, st = storage?'sessionStorage':'localStorage';
  for(let i=0; i<window[st].length; i++) {
    const key = window[st].key(i);
    items[key] = window[st].getItem(key);
  }
  return items;
}

// ============================================================================

time=function(){ return new Date().getTime(); };

unixtime2str = function(x,s='Y-m-d H:i:s') { // convert unixtime to string
    var d = new Date(x * 1000); // Convert Unix time to milliseconds
    function dd(x) { return ("0"+x).slice(-2) }
    return s.replace('Y',d.getFullYear())
        .replace('m',dd(d.getMonth()+1) ) // Months are zero-based
        .replace('d',dd(d.getDate()) )
        .replace('H',dd(d.getHours()) )
        .replace('i',dd(d.getMinutes()) )
        .replace('s',dd(d.getSeconds()) );
};


//==========

function plays(url,silent){ // silent: 1 - только загрузить, 0 - петь, 2 - петь НЕПРЕМЕННО, невзирая на настройки
    var audio = new Audio(url);
    audio.muted = silent==1;
    audio.play();
}

h=function(s){
    return (''+s).replace(/\&/sg,'&'+'amp;').replace(/\</sg,'&'+'lt;').replace(/\>/sg,'&'+'gt;').replace(/\'/sg,'&'+'#039;').replace(/\"/sg,'&'+'#034;'); // '
}


/*********************** majax ***********************/
// var ajaxgif = "<img src='img/ajax.gif'>";
var ajaxgif = "<img src='img/G6.svg'>";
//================================================================================
/*
progress=function(name,now,total,text) { name='progress'+(name?'_'+name:'');
    if(!dom(name)) { if(!total) return;
            helpc(name,"\
<div id='"+name+"_proc' style='text-align:center;font-size:23px;font-weight:bold;color:#555;'>0 %</div>\
<div id='"+name+"_tab' style='width:"+Math.floor(getWinW()/2)+"px;border:1px solid #666;'>\
<div id='"+name+"_bar' style='width:0;height:10px;background-color:red;'></div></div>");
    } else if(!total) return clean(name);
    var proc=Math.floor(1000*(now/total))/10;
    var W=1*dom(name+'_tab').style.width.replace(/[^\d]+/g,'');
    dom(name+'_bar').style.width=Math.floor(proc*(W/100))+'px';
    if(!text) text=''+proc+' %'; else text=text.replace(/\%\%/g,proc);
    dom(name+'_proc',text);
};
ProgressFunc=function(e){ progress('ajax',e.loaded,e.total,sizer(e.total)+': %% %'); };
*/

function sizer(x,p=2) { var i=0; for(;x>=1024;x/=1024,i++){} return Math.round(x,p)+['b','Kb','Mb','Gb','Tb','Pb'][i]; } // если отправка более 30кб - показывать прогресс

//=======================================================
// скопировать
cpbuf=function(e,message){ if(typeof(e)=='object') e=e.innerHTML; // navigator.clipboard.writeText(e);
    var area = document.createElement('textarea');
    document.body.appendChild(area);
    area.value = e;
    area.select();
    document.execCommand('copy');
    document.body.removeChild(area);
    if(message===undefined) message=1000;
    if(message) salert(`<div style='font-size:12px'>Copied to clipboard</div>

<p><textarea style="max-width:300px; height:80px; font-size:10px;">${h(e)}</textarea>
`,1*message);
};

/*****************************/
lightgreen=function(s) { return "<font color='"+arguments.callee.name+"'>"+s+"</font>"; }
green=function(s) { return "<font color='"+arguments.callee.name+"'>"+s+"</font>"; }
red=function(s) { return "<font color='"+arguments.callee.name+"'>"+s+"</font>"; }
blue=function(s) { return "<font color='"+arguments.callee.name+"'>"+s+"</font>"; }

// новые функции DOM чтоб не стыдно было за быдлоимена

dom=function(e,text){
    if(e==undefined) return false;
    if(text==undefined) return typeof(e)=='object' ? e : ((''+e).indexOf('.')===0 ? document.querySelectorAll(e)[0] : document.getElementById(e) );
    dom.s(e,text);
};

dom.s=function(e,text) {
    if(typeof(e)!='object') {
	if(e.indexOf && e.indexOf('.')===0) return document.querySelectorAll(e).forEach(l=>l.innerHTML=text);
	e=dom(e);
    } if(!e) return '';
    if(text==undefined) return ( e.value!=undefined ? e.value : e.innerHTML );
    if(e.value!=undefined) e.value=text;
    else { if(e.innerHTML!=undefined) e.innerHTML=text; /*init_tip(e);*/ }
};

dom.add=function(e,s,ara) { newdiv(s,ara,dom(e),'last'); };

dom.add1=function(e,s,ara) { newdiv(s,ara,dom(e),'first'); };

dom.on=function(e){ if(e=dom(e)) e.style.display='block'; };

dom.off=function(e){ if(e=dom(e)) { e.style.display='none'; if(e.id!='tip') dom.off('tip'); } };

dom.toggle=function(e){ if(e=dom(e)) { e.style.display = e.style.display==='none' ? 'block' : 'none'; if(e.id!='tip') dom.off('tip'); } };


dom.class=function(e,text) { document.querySelectorAll( e.indexOf('.')===0?e:'.'+e ).forEach(l=>l.innerHTML=text) };

//======================================================= mpers
/*
loadFile = async function(url) {
    try {
        const response = await fetch(url);
        if(!response.ok) throw new Error(`HTTP error status: ${response.status}`);
        const text = await response.text();
        return text;
    } catch (error) {
        console.error(`Failed to load file: ${error.message}`);
    }
};
*/

// mpers

mpersf=async function(file,ar){
    if(typeof("MPERS_TEMPLATES")!='object') MPERS_TEMPLATES={};
    if(!MPERS_TEMPLATES[file]) MPERS_TEMPLATES[file] = await loadFile(file);
    return mpers(MPERS_TEMPLATES[file],ar);
};

// del == true РЈРґР°Р»СЏС‚СЊ РїСѓСЃС‚С‹Рµ

mpers=function(s,ar,del){ if(del==undefined) del=true;
    var stop=1000,s0=false,c;
    while(--stop && s0!=s && (c=mpers.find(s)) ) {
	s0=s;
	var c0=c.substring(1,c.length-1); // то, что в фигурных скобках

// var msx=performance.now();
	x=mpers.do(ar, c0, del);
// if((msx=(performance.now()-msx)) > 50) console.log(`mpers.do ${msx} mpers_find=${SET.mpers_find} mpers_find_count=${SET.mpers_find_count}`);

	if(x!==false) {
	    s=s.replace(c,x);
	} else {
	    var c1=mpers(c0,ar,del);
	    if(c1!=c0) s=s.replace(c0,c1);
	}
    }
    return s;
};

mpers.ar=function(ar,name){
 try {
    var v = ar;
    if(name=='') return ar;
    name.split('.').forEach(n => {
	if(typeof(v[n])==undefined) return undefined;
	v = v[n];
    });
    return v;
 } catch(er) { return undefined; }
},

mpers.do=function(ar,s,del) {

    var m,v,x='',X;

    // Простые переменные {name}, {#name}
    if(null !== (m=s.match(/^(\#|)([0-9a-zA-Z_\.]+)$/)) ) {
	var [,mod,name] = m;
	if((v=mpers.ar(ar,name))===undefined) return (del ? '' : '{'+s+'}');
	return (mod=='#' ? h(v) : v);
    }

    // Операторы {opt(name):value} if(), for(), case(), date()
    if(null !== (m = s.match(/^([a-z]+)\(([0-9a-zA-Z_\.]*)\)\:([\s\S]*)/m) ) ) {
	var [,opt,name,value] = m;
	v=mpers.ar(ar,name);

//	const vif = (v||false) && v !== "0" && v != "false" && v != "null" && v !== "undefined" ;
	const vif = (
	    v === undefined || v === null || v === 0 || v === false
	    || (typeof v === "string" && ["0","false","null","undefined"].includes(v))
	) ? 0 : 1;

	if(opt=='noif') return (vif ? '' : value);
	if(opt=='if') return (vif ? value : '');

	if(opt=='case') {
	    var st=100, c;
	    while(--st && (c=mpers.find(value)) ) {
		if(null !== (m=c.match(/^\{([^\:]*)\:([\s\S]*)\}$/m)) ) {
		    var [,id,val] = m;
		    if(id==v) return val;
		    if(id==(''+v)) return val;
		    if(id=='*'||id=='default') x=val;
		}
		value = value.replace(c,'');
	    }
	    return x;
	}

	if(v===undefined) return '';

	if(opt=='for') {
	    try { // [!!!]
		v.forEach((item,i)=> { x+=mpers( value ,{...ar, ...item, ...{i:i,i1:i+1,item:item} }); } );
	    } catch(e) {
	        console.error('mpers '+e+'\nfor('+name+'){\n'+value+'\n}');
	        console.error('v('+typeof(v)+')=');
	        console.error(v);
	        console.error('-------- ar:');
	        console.error(ar);
	    }
	    return x;
	}

	if(opt=='date') { // date(time)Y-m-d H:i:s
	    return unixtime2str(v,value);
	}

	return false; // не наш случай
    }

    // {oper:text}
    if(null !== (m=s.match(/^([0-9a-z\#\.]+)\:([\s\S]*)/m)) ) {
     var [,oper,text] = m;


     // операции с текстом
     if(oper=='no') return '';

     // операции с текстом или переменной
     v = mpers.ar(ar,text);

     // stringify массива
     if(oper=='stringify') return JSON.stringify(v);

     x = (v!==undefined ? v : text);
     if(oper=='#') return h_fs(x);
     if(oper=='nl2br') return x.replace(/\n/g,"<br/>");
     if(oper=='#nl2br') return h_fs(x).replace(/\n/g,"<br/>"); // \n в <br\> и еще экранировать HTML-сущности
     if(oper=='url'||oper=='urlencode') return encodeURIComponent(x);
     if(oper=='urldecode') return x=decodeURIComponent(x);

     // операции с переменной
     if(! /^[0-9a-z_\.]+$/.test(text) ) return false; // не имя переменной
     if(v===undefined) return ''; // нет переменной в массиве
     if(oper=='c') return v.replace(/^\s+/g,'').replace(/\s+$/g,'');
     if(oper=='length') return v.length; // число символов в тексте
     if(oper=='date') return unixtime2str(v,'Y-m-d H:i:s'); // число в дату
     if(oper=='dat') return unixtime2str(v,'Y-m-d H:i'); // число в дату без секунд
     if(oper=='day') return unixtime2str(v,'Y-m-d'); // число в дату дня
     if(oper=='.') return (1*v).toFixed(0); // {.00:}123.456 -> 123.4
     if(oper=='.0') return (1*v).toFixed(1); // {.00:}123.456 -> 123.4
     if(oper=='.00') return (1*v).toFixed(2); // 123.456 -> 123.45
     if(oper=='.0000') return (1*v).toFixed(4); // 123.456 -> 123.4560
     return false;
    }

    return false;
};

// Поиск содержимого между парными скобками
mpers.find = function(s){
    var k, start=0, i, a,b, stop=1000, len=s.length;
    while( --stop ) {
	    k=1, start=s.indexOf('{',start); // }
	    if(start<0) return false;

	    i=start+1;
	    while( --stop && k!=0 && i<len ) { // пока есть чо
		a = s.indexOf('{',i); if( a<0 ) a=len;
		b = s.indexOf('}',i); if( b<0 ) b=len;
		if(a==b) break;
		if(a<b) { k++; i=a+1; } else { k--; i=b+1; }
	    }
	    if(!stop) console.log(`mpers.fing stop1 > 1000`);
	    if(k==0) return s.substring(start,i);
	    start++;
    }
    console.log(`mpers.fing stop > 1000`);
    return false;
};


AJAX=function(url,opt,s) {

  if(!opt) opt={}; else if(typeof(opt)=='function') opt={callback:opt};
  var async=(opt.async!==undefined?opt.async:true);
  try{
    if(!async && !opt.callback) opt.callback=function(){};
    if(!opt.noajax) ajaxon();
    var xhr=new XMLHttpRequest();

    xhr.onreadystatechange=function(){
    try{
      if(this.readyState==4) {
        if(!opt.noajax) ajaxoff();
	progress('ajax');
	if(this.status==200 && this.responseText!=null) {
            if(this.callback) this.callback(this.responseText,url,s);
            else eval(this.responseText);
	} else if(this.status==500) {
	    if(this.onerror) this.onerror(this.responseText,url,s);
	    else if(opt.callback) opt.callback(false,url,s);
	}
      }
     } catch(er){
	    alert(er);
	    console.error('Error Ajax: '+er+'\n\n'+this.responseText);
	}
    };

    for(var i in opt) xhr[i]=opt[i];
    xhr.open((opt.method?opt.method:(s?'POST':'GET')),url,async);

    if(s) {
        if(typeof(s)=='object' && !(s instanceof FormData) ) {
          var formData = new FormData();
          for(var i in s) formData.append(i,s[i]);
          var k=0; Array.from(formData.entries(),([key,D])=>(k+=(typeof(D)==='string'?D.length:D.size)));
          if(k>20*1024) xhr.upload.onprogress=ProgressFunc;
          xhr.send(formData);
        } else xhr.send(s);
    } else xhr.send();

    if(!async) return ( (xhr.status == 200 && xhr.readyState == 4)?xhr.responseText:false ); //xhr.statusText=='OK' // в хроме не работает блять

  } catch(e) { if(!async) return false; }
};

function AGET(url,s) { return AJAX(url,{noajax:1,async:false},s); } // асинхронно просто вернуть результат
function AJ(url,callback,s) { AJAX(url,{callback:callback,noajax:1},s); }

// ajaxon=ajaxoff=function(){};

ajaxon=function(){
    if(!document.querySelector('.ajax')) {
        const e = document.createElement('div');
        e.className = 'ajax';
        e.addEventListener('click', function() { this.remove(); });
        e.innerHTML = `
  <style>
    .ajax {
      position: fixed;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      z-index: 1000;
      display: flex;
      align-items: center;
      justify-content: center;
      backdrop-filter: blur(2px);
      -webkit-backdrop-filter: blur(2px); /* Safari */
    }
  </style>

<img src="./img/G6.svg">`;
        document.body.appendChild(e);
    }
};
ajaxoff=function(){
    const e = document.querySelector('.ajax');
    if(e) e.remove();
}


progress=function(name,now,total,text) { name='progress'+(name?'_'+name:'');
    if(!dom(name)) { if(!total) return;
        ohelpc(name,``,`
	    <div id='${name}_proc' style='text-align:center;font-size:23px;font-weight:bold;color:#555;'>0 %</div>
	    <div id='${name}_tab' style='width:${Math.floor(getWinW()/2)}px;border:1px solid #666;'>
	    <div id='${name}_bar' style='width:0;height:10px;background-color:red;'></div></div>
	`);
    } else if(!total) return clean(name);
    var proc=Math.floor(1000*(now/total))/10;
    var W=1*dom(name+'_tab').style.width.replace(/[^\d]+/g,'');
    dom(name+'_bar').style.width=Math.floor(proc*(W/100))+'px';
    if(!text) text=''+proc+' %'; else text=text.replace(/\%\%/g,proc);
    dom(name+'_proc',text);
};

function sizer(x) {  var i=0; for(;x>=1024;x/=1024,i++){} return Math.round(x,2)+['b','Kb','Mb','Gb','Tb','Pb'][i]; } // если отправка более 30кб - показывать прогресс

ProgressFunc=function(e){ progress('ajax',e.loaded,e.total,sizer(e.total)+': %% %'); };

/* log console */

log=function(s,color){
    // console.log(`[console:${color}] ${s}`);
    const e=dom('.log_console');
    // e.style.display='block';
    e.innerHTML = e.innerHTML + "<br>" + (color ? `<font color='${color}'>${h(s).replace(/\n/g,'<br>')}</font>` : h(s));
    e.scrollTo({ top: e.scrollHeight, behavior: 'smooth' });
};

log.bin=function(s){
    const e=dom('.log_console');
    e.innerHTML = e.innerHTML + s;
    e.scrollTo({ top: e.scrollHeight, behavior: 'smooth' });
};

log.set=function(s) { log(s,'orange'); }
log.ok=function(s) { log(s,'green'); }
log.err=function(s) { log(s,'red'); if(window.DOT?.progress?.stop) DOT.progress.stop(); return false; }
log.key=function(s) {
        if(CR.PGP.test_public(s)) return "[OK: PGP PUBLIC KEY]";
        if(CR.PGP.test_private(s)) return "[OK: PGP PRIVATE KEY]";
        return "error";
};

if(!window.dier) idie=dier=function(a,head){
    var s='';
    if(typeof(a) != 'object') s = h(a);
    else for(var i in a) s+=`<div>${h(i)}: ${h(a[i])}</div>`;
    dialog(s,head?head:'idie',{id:'idie'});
};


const www_design="./";

const mp3imgs={play:www_design+'img/play.png',pause:www_design+'img/play_pause.png',playing:www_design+'img/play_go.gif'};

stopmp3x=function(ee){ ee.src=mp3imgs.play; setTimeout("clean('audiosrcx_win')",50); };

changemp3x=function(url,name,ee,mode,viewurl,download_name) { //  // strt

    var ras = url.split('.').pop().toLowerCase();
    url = url.split('?')[0];

    var start=0,e;
    var s=name.replace(/^\s*([\d\:]+)\s.*$/gi,'$1'); if(s!=name&&-1!=s.indexOf(':')) { s=s.split(':'); for(var i=0;i<s.length;i++) start=60*start+1*s[i]; }

    var WWH="style='width:"+(Math.floor((getWinW()-50)*0.9))+"px;height:"+(Math.floor((getWinH()-50)*0.9))+"px;'";

    if(/(youtu\.be\/|youtube\.com\/)/.test(url) || (url.indexOf('.')<0 && /(^|\/)(watch\?v\=|)([^\s\?\/\&]+)($|\"|\'|\?.*|\&.*)/.test(url))) { // "

	var tt=url.split('?start=');
	if(tt[1]) { start=1*tt[1]; url=tt[0]; } // ?start=1232343 в секундах
	else {
	  var exp2=/[\?\&]t=([\dhms]+)$/gi; if(exp2.test(url)) { var tt=url.match(exp2)[0]; // ?t=7m40s -> 460 sec
	    if(/\d+s/.test(tt)) start+=1*tt.replace(/^.*?(\d+)s.*?$/gi,"$1");
	    if(/\d+m/.test(tt)) start+=60*tt.replace(/^.*?(\d+)m.*?$/gi,"$1");
	    if(/\d+h/.test(tt)) start+=3600*tt.replace(/^.*?(\d+)h.*?$/gi,"$1");
	  }
	}

	if(-1!=url.indexOf('://youtu') || -1!=url.indexOf('://www.youtu')) url=url.match(/(youtu\.be\/|youtube\.com\/)(embed\/|watch\?v\=|)([^\?\/]+)/)[3];

	return ohelpc('audiosrcx_win','YouTube '+h(name),"<div id=audiosrcx><center>\
<iframe "+WWH+" src=\"https://www.youtube.com/embed/"+h(url)+"?rel=0&autoplay=1"+(start?'&start='+start:'')+"\" frameborder='0' allowfullscreen></iframe>\
</center></div>");
    }

    else if(['mp4','avi','webm','mkv'].includes(ras)) s='<div>'+name+'</div><div><center><video controls autoplay id="audiidx" src="'+h(url)
	+'" width="640" height="480"><span style="border:1px dotted red">ВАШ БРАУЗЕР НЕ ПОДДЕРЖИВАЕТ MP4, МЕНЯЙТЕ ЕГО</span></video></center></div>';

    else if(['jpg','jpeg'].includes(ras)) { // panorama JPG
	s='<div>'+name+"</div><div id='panorama' "+WWH+"></div>";
	ohelpc('audiosrcx_win','<a class=r href="'+h(url)+'" title="download">'+h(url.replace(/^.*\//g,''))+'</a>','<div id=audiosrcx>'+s+'</div>');
	return LOADS(["//cdnjs.cloudflare.com/ajax/libs/three.js/r69/three.min.js",wwwhost+'extended/panorama.js'],function(){panorama_jpg('panorama',url)});
    }

/*
    else if(/([0-9a-z]{8}\-[0-9a-z]{4}\-[0-9a-z]{4}\-[0-9a-z]{4}\-[0-9a-z]{12})/.test(url) ) { // Peertube
	return ohelpc('audiosrcx_win','PeerTube '+h(name),"<div id=audiosrcx><center>\
<iframe "+WWH+" sandbox='allow-same-origin allow-scripts allow-popups' src=\""+h(url)+"\" frameborder='0' allowfullscreen></iframe>\
</div>");
    }
*/

    else s='<div><center><audio controls autoplay id="audiidx"><source src="'+h(url)
	+'" type="audio/mpeg; codecs=mp3"><span style="border:1px dotted red">ВАШ БРАУЗЕР НЕ ПОДДЕРЖИВАЕТ MP3, МЕНЯЙТЕ ЕГО</span></audio></center></div>';

    if(!viewurl) viewurl=url.replace(/^.*\//g,'');
    if(!download_name) download_name=url.replace(/^.*\//g,'');

    if(e=dom('audiidx')) {
        if(ee && ee.src && -1!=ee.src.indexOf('play_pause')){ ee.src=mp3imgs.playing; return e.play(); }
        if(ee && ee.src && -1!=ee.src.indexOf('play_go')){ ee.src=mp3imgs.pause; return e.pause(); }
        dom('audiosrcx',s);
        posdiv('audiosrcx_win',-1,-1);
        e=dom('audiidx');
        e.currentTime=start;
    } else {
        ohelpc('audiosrcx_win','<a class=r href="'+h(url)+'" title="Download: '+h(download_name)+'" download="'+h(download_name)+'">'+h(viewurl)+'</a>','<div id=audiosrcx>'+s+'</div>');
        e=dom('audiidx');
        e.currentTime=start;
    }

    if(ee) addEvent(e,'ended',function(){ stopmp3x(ee) });
    if(ee) addEvent(e,'pause',function(){ if(e.currentTime==e.duration) stopmp3x(ee); else ee.src=mp3imgs.pause; });
    if(ee) addEvent(e,'play',function(){ ee.src=mp3imgs.playing; });
}



err = function(s) {
    log.err(`Fatal error: ${s}`);
    ohelpc('error','Fatal error', s);
};

h_fs=function(s){
    s=h(s);
    return s.replace(/\{/g, '&#123;').replace(/\}/g, '&#125;');
}