(() => {
  'use strict';
  const d = document;
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const $ = (s, r = d) => r.querySelector(s);
  const $$ = (s, r = d) => Array.from(r.querySelectorAll(s));
  const hasIO = 'IntersectionObserver' in window;

  const onView = (els, fn, opts = { threshold: 0.25 }) => {
    if (!hasIO) { els.forEach(fn); return; }
    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => { if (e.isIntersecting) { io.unobserve(e.target); fn(e.target); } });
    }, opts);
    els.forEach((el) => io.observe(el));
  };

  /* número en formato español: 1.325 · 7,4 */
  const fmt = (n, dec = 0) => {
    const [i, f] = Math.abs(n).toFixed(dec).split('.');
    const g = i.replace(/\B(?=(\d{3})+(?!\d))/g, '.');
    return (n < 0 ? '−' : '') + g + (f ? ',' + f : '');
  };
  const ease = (t) => 1 - Math.pow(2, -10 * t); // ease-out-expo
  const tween = (from, to, ms, step) => {
    const t0 = performance.now();
    const tick = (now) => {
      const t = Math.min(1, (now - t0) / ms);
      step(from + (to - from) * (t === 1 ? 1 : ease(t)));
      if (t < 1) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  };

  /* cabecera */
  const top = $('.top');
  const onScroll = () => top.classList.toggle('scrolled', scrollY > 8);
  addEventListener('scroll', onScroll, { passive: true }); onScroll();

  /* entradas escalonadas */
  onView($$('[data-r]'), (el) => el.classList.add('in'), { threshold: 0.15, rootMargin: '0px 0px -8% 0px' });

  /* contadores: el valor final ya está en el HTML */
  const count = (el) => {
    const to = parseFloat(el.dataset.count), dec = +(el.dataset.dec || 0);
    const pre = el.dataset.pre || '', suf = el.dataset.suf || '';
    if (reduce) return;
    tween(0, to, to > 1000 ? 2000 : 1500, (v) => { el.textContent = pre + fmt(v, dec) + suf; });
  };
  onView($$('[data-count]'), count, { threshold: 0.6 });

  /* ---------- Cómo trabajamos: maqueta fija que cambia con el scroll (escritorio); clic en cada paso ---------- */
  const steps = $$('.step');
  const stageIn = $('.stage-in');
  const dots = $$('.stage .dots i');
  const mocks = steps.map((s) => $('.mock', s));
  const slots = steps.map((s) => $('.mock-slot', s));
  const desk = matchMedia('(min-width: 961px)');
  const rootEl = d.documentElement;
  const grid = $('.how-grid');
  const hdr = $('.top');
  const SP = 1.05; // scroll de cada paso: 105 vh (nunca menos de 80 vh)
  let pin = false, active = -1, lockUntil = 0, f = 0;
  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
  const turnOn = (m) => { m.classList.remove('is-on'); void m.offsetWidth; m.classList.add('is-on'); };
  const hh = () => (hdr ? hdr.offsetHeight : 80);
  const setActive = (i) => {
    i = clamp(i, 0, steps.length - 1);
    if (i === active) return;
    active = i;
    steps.forEach((s, k) => s.classList.toggle('is-active', k === i));
    dots.forEach((dt, k) => dt.classList.toggle('on', k === i));
    if (pin) mocks.forEach((m, k) => { m.classList.toggle('was', k < i); if (k === i) turnOn(m); else m.classList.remove('is-on'); });
  };
  const place = () => {
    pin = desk.matches && !reduce;
    rootEl.classList.toggle('pin-on', pin);
    rootEl.style.setProperty('--hh', hh() + 'px');
    if (pin) mocks.forEach((m) => stageIn.appendChild(m));
    else mocks.forEach((m, k) => { slots[k].appendChild(m); m.classList.remove('was'); m.classList.add('is-on'); });
    const a = active; active = -1; setActive(Math.max(0, a)); update();
  };
  /* escena fija: el paso depende del avance de scroll dentro de la pista (105 vh por paso), con margen para que no salte */
  const update = () => {
    if (!pin) return;
    const sp = innerHeight * SP;
    f = (hh() - grid.getBoundingClientRect().top) / sp;
    let idx = clamp(Math.floor(f), 0, steps.length - 1);
    if (idx > active && f < active + 1 + 0.08) idx = active;
    if (idx < active && f > active - 0.08) idx = active;
    if (idx !== active && performance.now() >= lockUntil) setActive(idx);
    const cur = steps[active];
    if (cur) cur.style.setProperty('--prog', clamp(f - active, 0, 1).toFixed(3));
  };
  let ticking = false;
  const onPinScroll = () => { if (ticking) return; ticking = true; requestAnimationFrame(() => { ticking = false; update(); }); };
  addEventListener('scroll', onPinScroll, { passive: true });
  addEventListener('resize', () => { rootEl.style.setProperty('--hh', hh() + 'px'); update(); });
  place();
  desk.addEventListener('change', place);
  const goTo = (k) => {
    k = clamp(k, 0, steps.length - 1);
    lockUntil = 0;
    if (pin) {
      const top = scrollY + grid.getBoundingClientRect().top - hh() + (k + 0.3) * innerHeight * SP;
      setActive(k);
      scrollTo({ top, behavior: 'smooth' });
    } else {
      setActive(k);
      if (desk.matches) steps[k].scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'center' });
    }
  };
  steps.forEach((s, k) => $('.step-h', s).addEventListener('click', () => goTo(k)));
  $('.st-prev').addEventListener('click', () => goTo(active - 1));
  $('.st-next').addEventListener('click', () => goTo(active + 1));

  /* ---------- Visor de documentos de varias páginas (flechas, teclado y gesto táctil) ---------- */
  const viewers = $$('[data-viewer]').map((v) => {
    const pages = $$('.vw-page', v), n = $('.vw-n', v);
    let cur = 0, holdT = 0;
    const hold = () => { lockUntil = performance.now() + 1800; clearTimeout(holdT); holdT = setTimeout(update, 1850); };
    const show = (i, back) => {
      cur = (i + pages.length) % pages.length;
      pages.forEach((pg, k) => { pg.classList.toggle('is-on', k === cur); pg.classList.toggle('back', !!back); });
      n.textContent = (cur + 1) + '/' + pages.length;
      hold();
    };
    $('.vw-prev', v).addEventListener('click', () => show(cur - 1, true));
    $('.vw-next', v).addEventListener('click', () => show(cur + 1, false));
    v.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowRight') { e.preventDefault(); e.stopPropagation(); show(cur + 1, false); }
      if (e.key === 'ArrowLeft') { e.preventDefault(); e.stopPropagation(); show(cur - 1, true); }
    });
    let x0 = null, y0 = 0;
    v.addEventListener('touchstart', (e) => { x0 = e.touches[0].clientX; y0 = e.touches[0].clientY; }, { passive: true });
    v.addEventListener('touchend', (e) => {
      if (x0 === null) return;
      const dx = e.changedTouches[0].clientX - x0, dy = e.changedTouches[0].clientY - y0; x0 = null;
      if (Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy) * 1.5) show(cur + (dx < 0 ? 1 : -1), dx > 0);
    }, { passive: true });
    const srcs = pages.map((pg) => $('img', pg));
    $$('.vw-zoom', v).forEach((b, k) => b.addEventListener('click', () => openLb({ srcs, show, from: b }, k)));
    return { el: v, show: (dir) => show(cur + dir, dir < 0), goto: (k, back) => show(k, back) };
  });
  /* ampliar página: lightbox con flechas, teclado y gesto */
  const lb = $('#lb'), lbImg = $('.lb-img', lb), lbN = $('.lb-n', lb), lbSc = $('.lb-sc', lb);
  let lbV = null, lbK = 0, lbFrom = null;
  function openLb(v, k) {
    lbV = v; lbFrom = v.from; lb.hidden = false; rootEl.classList.add('lb-open');
    lbShow(k); $('.lb-x', lb).focus();
  }
  function lbShow(k, back) {
    const n = lbV.srcs.length; lbK = (k + n) % n;
    const im = lbV.srcs[lbK];
    lbImg.src = im.currentSrc || im.src; lbImg.alt = im.alt; lbN.textContent = (lbK + 1) + '/' + n;
    lbSc.scrollTop = 0; lbSc.scrollLeft = 0;
    lbV.show(lbK, back);
  }
  const closeLb = () => { lb.hidden = true; rootEl.classList.remove('lb-open'); if (lbFrom) lbFrom.focus({ preventScroll: true }); lbV = null; };
  $('.lb-x', lb).addEventListener('click', closeLb);
  lb.addEventListener('click', (e) => { if (e.target === lb || e.target === lbSc) closeLb(); });
  $('.lb-prev', lb).addEventListener('click', () => lbShow(lbK - 1, true));
  $('.lb-next', lb).addEventListener('click', () => lbShow(lbK + 1));
  lb.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); closeLb(); }
    else if (e.key === 'ArrowRight') { e.preventDefault(); e.stopPropagation(); lbShow(lbK + 1); }
    else if (e.key === 'ArrowLeft') { e.preventDefault(); e.stopPropagation(); lbShow(lbK - 1, true); }
    else if (e.key === 'Tab') {
      const f = $$('button', lb), a = d.activeElement;
      if (e.shiftKey && a === f[0]) { e.preventDefault(); f[f.length - 1].focus(); }
      else if (!e.shiftKey && a === f[f.length - 1]) { e.preventDefault(); f[0].focus(); }
    }
  });
  let lx = null, ly = 0;
  lbSc.addEventListener('touchstart', (e) => { lx = e.touches[0].clientX; ly = e.touches[0].clientY; }, { passive: true });
  lbSc.addEventListener('touchend', (e) => {
    if (lx === null) return;
    const dx = e.changedTouches[0].clientX - lx, dy = e.changedTouches[0].clientY - ly; lx = null;
    const atEdge = dx < 0 ? lbSc.scrollLeft + lbSc.clientWidth >= lbSc.scrollWidth - 4 : lbSc.scrollLeft <= 4;
    if (atEdge && Math.abs(dx) > 70 && Math.abs(dx) > Math.abs(dy) * 1.5) lbShow(lbK + (dx < 0 ? 1 : -1), dx > 0);
  }, { passive: true });
  /* con la escena fija, las flechas del teclado pasan las páginas del ejemplo del paso activo */
  d.addEventListener('keydown', (e) => {
    if (!pin || e.defaultPrevented || e.altKey || e.ctrlKey || e.metaKey || e.shiftKey) return;
    if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return;
    if (/^(INPUT|TEXTAREA|SELECT)$/.test((e.target.tagName || ''))) return;
    const v = viewers.find((x) => x.el.classList.contains('is-on'));
    const r = grid.getBoundingClientRect();
    if (!v || r.top > hh() + 4 || r.bottom < innerHeight * 0.5) return;
    e.preventDefault(); v.show(e.key === 'ArrowRight' ? 1 : -1);
  });

  /* ---------- Mapa ---------- */
  onView([$('.map')], (el) => el.classList.add('on'), { threshold: 0.3 });

  /* ---------- El proceso: camino que une los nodos, con puntos que viajan ---------- */
  const fl2 = $('.fl2');
  if (fl2) {
    const anchors = $$('.fn', fl2).map((n) => $('.ring', n) || $('.calcard', n) || $('.cloud', n));
    const base = $('.fl2-base', fl2), dash = $('.fl2-dash', fl2);
    const mainDots = $$('.fl2-dot:not(.s)', fl2), strandDots = $$('.fl2-dot.s', fl2);
    const hot = $$('.cloud i.hot', fl2);
    const layout = () => {
      const fr = fl2.getBoundingClientRect();
      const c = (el, side) => { const r = el.getBoundingClientRect(); return { x: (side === 'l' ? r.left : side === 'r' ? r.right : r.left + r.width / 2) - fr.left, y: r.top + r.height / 2 - fr.top, t: r.top - fr.top, b: r.bottom - fr.top }; };
      let main = '', strands = [];
      if (desk.matches) {
        const pts = [c(anchors[1])].concat(anchors.slice(2, 6).map((a) => c(a)), [c(anchors[6], 'l')]);
        main = 'M' + pts[0].x + ' ' + pts[0].y;
        for (let k = 1; k < pts.length; k++) {
          const a = pts[k - 1], b = pts[k], mx = (a.x + b.x) / 2;
          main += 'C' + mx + ' ' + a.y + ' ' + mx + ' ' + b.y + ' ' + b.x + ' ' + b.y;
        }
        const f = pts[0];
        strands = hot.map((h) => { const o = c(h); const mx = (o.x + f.x) / 2; return 'M' + o.x + ' ' + o.y + 'C' + mx + ' ' + o.y + ' ' + mx + ' ' + f.y + ' ' + f.x + ' ' + f.y; });
      } else {
        const top = c(anchors[1]), last = c(anchors[4]);
        const x = top.x;
        main = 'M' + x + ' ' + (c(anchors[0]).b) + 'V' + (c(anchors[6]).t);
        strands = [];
      }
      base.setAttribute('d', main + strands.join(''));
      dash.setAttribute('d', main);
      mainDots.forEach((dt) => { dt.style.offsetPath = 'path("' + main + '")'; });
      strandDots.forEach((dt, k) => { if (strands[k]) { dt.style.offsetPath = 'path("' + strands[k] + '")'; dt.hidden = false; } else dt.hidden = true; });
      fl2.classList.add('ready');
    };
    layout();
    addEventListener('resize', layout, { passive: true });
    d.fonts && d.fonts.ready.then(layout);
    desk.addEventListener('change', layout);
  }

  /* ---------- Hero: la bandeja en marcha ---------- */
  const app = $('.app');
  if (app) {
    const k = (n) => $('[data-k="' + n + '"]', app);
    const t = (n) => $('[data-t="' + n + '"]', app);
    const toast = $('.app-list .new', app), meet = $('.meet', app);
    const bumpK = (el, v) => { el.textContent = v; el.classList.remove('bump'); void el.offsetWidth; el.classList.add('bump'); };
    const seq = [
      { time: '12:05', name0: 'Ana Lorenzo', subj: 'Re: Frío Industrial Lérez · «Buen momento. ¿Tienes hueco esta semana?»', name: 'Ana Lorenzo', day: 'Mar', hour: '12:30', rep: 7, meet: 3 },
      { time: '16:20', name0: 'Xosé Pereira', subj: 'Re: Talleres Arnoia · «Me interesa. ¿Podemos hablar el viernes?»', name: 'Xosé Pereira', day: 'Vie', hour: '09:30', rep: 8, meet: 4 },
      { time: '11:40', name0: 'Marta Iglesias', subj: 'Re: Conservas do Morrazo · «¿Lo hablamos el jueves?»', name: 'Marta Iglesias', day: 'Jue', hour: '10:00', rep: 6, meet: 2 },
    ];
    let n = 0, visible = true, hover = false;
    if (hasIO) new IntersectionObserver((e) => { visible = e[0].isIntersecting; }).observe(app);
    app.addEventListener('mouseenter', () => { hover = true; });
    app.addEventListener('mouseleave', () => { hover = false; });
    const step = () => {
      if (!visible || hover || d.hidden) return;
      const s = seq[n++ % seq.length];
      toast.style.animation = 'none'; meet.style.animation = 'none';
      toast.classList.add('out'); meet.classList.add('out');
      setTimeout(() => {
        t('time').textContent = s.time; t('name0').textContent = s.name0; t('subj').textContent = s.subj;
        toast.classList.remove('out');
        bumpK(k('rep'), s.rep);
      }, 450);
      setTimeout(() => {
        t('name').textContent = s.name; t('day').textContent = s.day; t('hour').textContent = s.hour;
        meet.classList.remove('out');
        bumpK(k('meet'), s.meet);
      }, 1500);
    };
    if (!reduce) setInterval(step, 6000);
  }

  /* ---------- Antes / después ---------- */
  /* comparador con asa, el mismo patrón que la web de Webnify: barrido de demostración al 40 % visible;
     cualquier toque, rueda o tecla lo cancela; con ratón, la línea sigue al puntero */
  const cmp = $('#comparador');
  if (cmp) {
    const scr = $('.cmp-screen', cmp), rango = $('.cmp-range', cmp), capaD = $('.cmp-despues', cmp), linea = $('.cmp-line', cmp), asa = $('.cmp-handle', cmp);
    const fino = matchMedia('(hover: hover) and (pointer: fine)').matches;
    rango.hidden = false;
    let demo = 0;
    const setX = (v) => {
      v = Math.max(0, Math.min(100, v));
      capaD.style.clipPath = 'inset(0 0 0 ' + v.toFixed(2) + '%)';
      linea.style.transform = 'translate3d(' + v.toFixed(2) + '%,0,0)';
      rango.value = Math.round(v);
      rango.setAttribute('aria-valuetext', 'Antes al ' + Math.round(v) + ' %');
    };
    const corta = () => { if (demo) { cancelAnimationFrame(demo); demo = 0; } };
    rango.addEventListener('input', () => { corta(); setX(+rango.value); });
    ['pointerdown', 'wheel', 'keydown', 'touchstart'].forEach((ev) => scr.addEventListener(ev, corta, { passive: true }));
    scr.addEventListener('pointerdown', () => scr.classList.add('arrastra'));
    addEventListener('pointerup', () => scr.classList.remove('arrastra'));
    if (fino) {
      scr.addEventListener('pointermove', (e) => {
        if (e.pointerType !== 'mouse' || demo) return;
        const r = scr.getBoundingClientRect();
        setX((e.clientX - r.left) / r.width * 100);
      }, { passive: true });
    }
    const inOut = (k) => (k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2);
    const out = (k) => 1 - Math.pow(1 - k, 3);
    const tramo = (a, b, ms, e, luego) => {
      const t0 = performance.now();
      const f = (t) => {
        const k = Math.min(1, (t - t0) / ms);
        setX(a + (b - a) * e(k));
        if (k < 1) demo = requestAnimationFrame(f); else { demo = 0; if (luego) luego(); }
      };
      demo = requestAnimationFrame(f);
    };
    if (!reduce && hasIO) {
      setX(92);
      const io = new IntersectionObserver((es) => {
        if (!es[0].isIntersecting) return;
        io.disconnect();
        tramo(92, 8, 1100, inOut, () => tramo(8, 50, 700, out, () => asa.classList.add('late')));
      }, { threshold: 0.4 });
      io.observe(scr);
    } else setX(50);
  }
})();

/* Formulario de contacto. Variables en el HTML (ver PENDIENTES-V28.md):
   data-endpoint = URL de un servicio de formularios (POST JSON). Vacío: no hay envío desde la web; se abre el
   correo del usuario con el mensaje preparado hacia data-mailto (gp@reunvo.com) y se avisa de que aún no se ha enviado. */
(() => {
  const f = document.getElementById('form-contacto');
  if (!f) return;
  const msg = f.querySelector('.f-msg');
  const show = (html, tipo) => { msg.className = 'f-msg ' + tipo; msg.innerHTML = html; msg.hidden = false; };
  const esc = (t) => t.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  f.addEventListener('submit', (e) => {
    e.preventDefault();
    msg.hidden = true;
    let primero = null;
    f.querySelectorAll('input[required]').forEach((i) => {
      const bad = !i.value.trim() || (i.type === 'email' && !/^\S+@\S+\.\S+$/.test(i.value.trim()));
      i.setAttribute('aria-invalid', bad ? 'true' : 'false');
      const er = document.getElementById('err-' + i.name);
      if (er) {
        er.hidden = !bad;
        if (bad) i.setAttribute('aria-describedby', er.id); else i.removeAttribute('aria-describedby');
      }
      if (bad && !primero) primero = i;
    });
    if (primero) { primero.focus(); return; }
    const datos = Object.fromEntries(new FormData(f).entries());
    const url = f.dataset.endpoint;
    if (url) {
      fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(datos) })
        .then((r) => { if (!r.ok) throw new Error(); show('Solicitud enviada. Te escribiremos al correo que has indicado.', 'ok'); f.reset(); })
        .catch(() => show('No se ha podido enviar. Escríbenos a <a href="mailto:' + esc(f.dataset.mailto || '') + '">' + esc(f.dataset.mailto || '') + '</a>.', 'warn'));
      return;
    }
    const dir = f.dataset.mailto || '';
    const cuerpo = 'Nombre: ' + datos.nombre + '\nCorreo: ' + datos.email + (datos.firma ? '\nFirma: ' + datos.firma : '') + '\n\nQuiero pedir una llamada.';
    const href = 'mailto:' + dir + '?subject=' + encodeURIComponent('Pedir una llamada') + '&body=' + encodeURIComponent(cuerpo);
    show('Se abre tu programa de correo con el mensaje preparado. <b>Todavía no se ha enviado:</b> envíalo desde ahí, o escribe a <a href="' + esc(href) + '">' + esc(dir) + '</a>.', 'ok');
    location.href = href;
  });
})();
