DESIGN={};

async function INIT() {
//    nonav = 1;

    init_tip = center = function(){};

    ohelpc=function(id,header,s) { dialog(s,header,{id:id}); }

    clean=function(e){ if(typeof(e)==='string') e=dom(e); if(e) e.remove(); }

    salert = function(l,t) {
        var header,k=l.indexOf('<p>');
        if(k>=0) {
            header=l.substring(0,k);
            l=l.substring(k+3);
        } else {
            header='&nbsp;';
        }
        var id=dialog(l,header,{id:'salert'});
        if(t) setTimeout(()=>{dialog.close(id)},t);
        return false;
    };

    // Escape button
    document.addEventListener('keydown', function(event) {
        if(event.key === 'Escape') {
            var p = document.querySelectorAll('div.dialog');
            if(p.length > 0) setTimeout(()=>{ dialog.close(p[p.length-1]) }, 10); // Удаляем самый верхний открытый
	    return
        }

	// Ctrl+Enter
	if(event.ctrlKey && event.key === 'Enter') {
	    var p = document.querySelectorAll("[name='save']");
	    if(p && p[0]) p[0].click();
	}

    });

    // Closing windows when clicking outside their area
    document.addEventListener("click", function (event) {
        if(dom("user-info-btn") && !dom("user-info-btn").contains(event.target) && !dom("user-info-block").contains(event.target)) dom.off('user-info-block');
        if(LENA.isMobile()) {
            if(!dom("menu-toggle").contains(event.target) && !dom('left-menu').contains(event.target)) dom.off('left-menu');
        }

	// if(event.target.closest('.popup-window')) return;
	// document.querySelectorAll('div.dialog').forEach( e=>e.remove() );
    });


//    const menuToggle = document.getElementById dom("menu-toggle");
//    const userToggle = document.getElementById dom("user-info-btn");
//    const leftMenu = document.getElementById("left-menu");
//    const userInfoBlock = document.getElementById dom("user-info-block");
//    let mailbox_blocks = document.querySelectorAll(".mailbox-block");
//    const mailbox_inbox = document.getElementById("inbox");
//    const mailbox_sent = document.getElementById("sent");

    // Listen for window resize to reset display properties in desktop mode
    window.addEventListener("resize", function () {
        dom.off('user-info-block');
        dom('left-menu').style.display = LENA.isMobile() ? "none" : "flex"; // Ensure the menu is visible in desktop mode
    });

    // Get Design
    dom('template').querySelectorAll('.template').forEach(e=> DESIGN[e.getAttribute('name')]=e.innerHTML.replace(/<!-- *([^ ]+) *-->/g,'$1') );
    dom('template').remove();

//    memli();


/*
    var s=''; Object.keys(ACTS).forEach(l=>{
	if(l==='11111111111111111show_inbox'
//	    && l!='show_outbox'
//	    && l!='default'
//	    && l!='Message'
//	    && l!='Recipient'
//	    && l!='Register'
	) s+=`<div class='mv0' onclick="memli('${l}')">${l}</div>`
    });
    if(s) dom('menu',s);

*/



    // Open/close left menu.
    dom('menu-toggle').addEventListener("click", function () {
	const leftMenu=dom("left-menu");
        leftMenu.style.display = leftMenu.style.display === "block" ? "none" : "block";
    });

    dom.on('log_console');

    await INIT1();

    PINGER.box_all("inbox");
    PINGER.box_all("outbox");
    ACTS.show_inbox();



}

LENA = {
    isMobile: function() { return window.innerWidth <= 768; },
    hideLeftMenuMobile: function() { if(LENA.isMobile()) dom('left-menu').style.display = "none"; },
};



ACTS={
    default: function(){ memli('show_inbox'); },

    show_inbox: function(){
	// dom('mailbox,DESIGN.inbox);
	dom.off('outbox');
	dom.on('inbox');
	// PINGER.www_check(true);
	PINGER.box_all("inbox");
	LENA.hideLeftMenuMobile();
    },
    show_outbox: function(){
	dom.off('inbox');
	dom.on('outbox');
	// dom('mailbox,DESIGN.outbox);
	PINGER.box_all("outbox");
	LENA.hideLeftMenuMobile();
    },

//    message_dark: function(){ dialog('mailbox,'DESIGN.outbox',{color:'dark'}) },
//    message_light: function(){ dialog('mailbox,'DESIGN.outbox',{color:'light'}) },
    test_confirm: function(){ my_confirm('Купить слона?',{rcolor:'light'}) },

    testx: function(){ TESTX() },


    Register: function(){ dialog(DESIGN.register,"Identity form") },
    Message: function(){ LENA.hideLeftMenuMobile(); dialog(DESIGN.message,DESIGN.message_header); },
    Recipient: function(){
	console.log(DESIGN.recipient);
	dialog(mpers(DESIGN.recipient,{src:'src',recipients:[
	    {name: `Olivia Peterson`, email: `olivia.peterson@example.com`, img: "images/dots-logo.webp"},
	    {name: `James Carter`, email: `james.carter@example.com`, img: "images/dots-logo.webp"},
	    {name: `Emily Thompson`, email: `emily.thompson@example.com`, img: "images/dots-logo.webp"},
	    {name: `Michael Harris`, email: `michael.harris@example.com`, img: "images/dots-logo.webp"},
	    {name: `Sophia Martinez`, email: `sophia.martinez@example.com`, img: "images/dots-logo.webp"},
	]}),DESIGN.recipient_header,{color:'light'});
    },
};

memli=function(x) {
    if(!x) {
        var x = document.location.hash.replace(/^#/g,'');
        if(!x || !x.length) x = f5_read('memli');
        if(!x || !x.length || !ACTS[x]) x = 'default';
    }
    f5_save('memli',x);
    document.location.hash=x;
    return ACTS[x]();
};

dialog=function(s,header,set) { if(!set) set={};
    if(set && set.id) {
	var id = set.id, e = document.querySelector('dialog#'+id);
	if(e) { e.querySelector('.dialog-content').innerHTML = s; return id; }
    } else { var id = 'dialog_'+(++dialog.id); }
    var e = document.createElement('div'); // dialog
    e.className='dialog';
    e.id = id;
    e.innerHTML = mpers(DESIGN.dialog,{body:s,id:id,set:set,header:header,color: (set && set.color?set.color:'dark')}); // light
    document.body.appendChild(e);
    setTimeout(function(){ e.querySelector('.popup-overlay').classList.add('active'); },10);
    e.querySelector('.popup-close').addEventListener('click', function(event) {	dialog.close(id); });
    return id;
};
dialog.id=0;
dialog.close=function(e) {
    (typeof(e)=='object' ? [e] : document.querySelectorAll( e ? '#'+e : 'div.dialog') ).forEach(x=>{
	x.querySelector('.popup-overlay').classList.remove('active');
	setTimeout(() => { x.remove(); }, 300); // Таймаут для завершения анимации
    });
};

async function my_confirm(text, opt) {
    if(typeof(opt)!='object') opt={};
    if(!opt.yes) opt.yes='Yes';
    if(!opt.no) opt.no='No';
    var id='confirm_'+(''+Math.random()).replace('.','-');
    return new Promise((resolve) => {
        dialog(mpers(DESIGN.confirm,opt),mpers(DESIGN.confirm_header,{text:text}),{id:id});
        document.getElementById('my-confirm-yes').onclick = () => { dialog.close(id); resolve(true); };
        document.getElementById('my-confirm-no').onclick = () => { dialog.close(id); resolve(false); };
    });
}

// ==================================================================
let shake={
    // lastTime: Date.now(),
    threshold: 30, // Чувствительность тряски
    summ_th: 1000, // Чувствительность тряски за период
    summ: 0, // сумма
    start: Date.now(), // стартовое время
    period: 500,
    fn: (summ)=>{ ohelpc('shakeid','Problems?',`You are shaking your phone. Do you need a help?`); },
};


startShakeDetection=function() { // Запускаем обработку
window.addEventListener("devicemotion",(event) => {
    let a = event.accelerationIncludingGravity; if(!a) return;
    let acceleration = Math.sqrt(a.x*a.x + a.y*a.y + a.z*a.z);
    if(acceleration < shake.threshold) return;
    let time = Date.now();
    if(shake.start + shake.period > time) { // не на натрясли еще - просто суммируем
            shake.summ += acceleration;
    } else { // натрясли
            if(shake.start + shake.period*2 < time) { // это было слишком давно и не считается
                shake.start = time; // начали считать
                shake.summ = acceleration;
            } else { // сработало
                if(shake.summ > shake.summ_th) setTimeout("shake.fn("+shake.summ+")",0);
                shake.start = time;
                shake.summ = 0;
            }
    }
});
};

async function requestMotionPermission(mode) {
    if(typeof DeviceMotionEvent.requestPermission === "function") {
	try {
	    if(mode) return;
	    // alert(' '+DeviceMotionEvent.requestPermission);
            let permission = await DeviceMotionEvent.requestPermission();
            if(permission === "granted") startShakeDetection(); // Запускаем обработку
        } catch(er) { alert(er); }
    } else startShakeDetection(); // Запускаем обработку
}
requestMotionPermission(1);