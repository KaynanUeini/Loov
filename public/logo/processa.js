/*
  Tratamento do logo que o dono sobe — um arquivo só pro site (Gerenciar →
  Informações básicas) e pro app (editor.html, aberto numa janela web
  escondida). Mudou aqui, vale nos dois.

  Regra: cada logo fica com a PRÓPRIA forma, como os logos gerados pela Loov.
  Nada de moldura imposta (um logo redondo num quadrado branco deixava
  rebarba no card escuro do Last Minute).

  · Já tem fundo transparente (o PNG do designer): só corta as margens.
  · Fundo liso (o JPEG do WhatsApp, fundo branco ou de uma cor): tira o fundo,
    corta as margens. O dono pode desligar ("Remover fundo") se errar.
  · Foto sem fundo liso (a fachada): não tem forma própria; vai num quadrado
    de cantos arredondados, com os cantos transparentes.

  Sai sempre um PNG 512×512 com transparência, com o logo inteiro dentro.
*/
(function (g) {
  var LADO = 512;
  var FOLGA = 16;          // respiro em volta do logo com forma própria
  var RAIO = 0.22;         // canto do quadrado da foto (o mesmo do app)
  var TOL = 40;            // distância de cor que ainda conta como fundo
  var BORDA_LISA = 0.9;    // fração da borda que precisa ser do fundo

  function canvas(w, h) { var c = document.createElement('canvas'); c.width = w; c.height = h; return c; }

  // Imagem → canvas, com o maior lado em até `max` (foto de celular tem 4000 px).
  function canvasDe(img, max) {
    var k = Math.min(1, (max || 1024) / Math.max(img.width, img.height));
    var c = canvas(Math.max(1, Math.round(img.width * k)), Math.max(1, Math.round(img.height * k)));
    var x = c.getContext('2d'); x.imageSmoothingQuality = 'high';
    x.drawImage(img, 0, 0, c.width, c.height);
    return c;
  }

  function bordaIdx(w, h) {
    var idx = [], i;
    for (i = 0; i < w; i++) { idx.push(i); idx.push((h - 1) * w + i); }
    for (i = 1; i < h - 1; i++) { idx.push(i * w); idx.push(i * w + w - 1); }
    return idx;
  }

  // O que é o fundo da imagem: transparente, liso (e de que cor) ou nenhum.
  function analisar(cv) {
    var w = cv.width, h = cv.height, d = cv.getContext('2d').getImageData(0, 0, w, h).data;
    var idx = bordaIdx(w, h), transp = 0, caixas = {}, melhor = null;
    idx.forEach(function (p) {
      var o = p * 4;
      if (d[o + 3] < 16) { transp++; return; }
      var k = (d[o] >> 4) + ',' + (d[o + 1] >> 4) + ',' + (d[o + 2] >> 4);
      caixas[k] = (caixas[k] || 0) + 1;
      if (!melhor || caixas[k] > caixas[melhor]) melhor = k;
    });
    if (transp / idx.length >= 0.5) return { transparente: true, fundoLiso: false, cor: null };
    // Cor do fundo: média dos pixels de borda da cor mais comum.
    var soma = [0, 0, 0], n = 0;
    idx.forEach(function (p) {
      var o = p * 4;
      if (d[o + 3] < 16) return;
      if ((d[o] >> 4) + ',' + (d[o + 1] >> 4) + ',' + (d[o + 2] >> 4) !== melhor) return;
      soma[0] += d[o]; soma[1] += d[o + 1]; soma[2] += d[o + 2]; n++;
    });
    var cor = n ? [soma[0] / n, soma[1] / n, soma[2] / n] : [255, 255, 255];
    var perto = 0;
    idx.forEach(function (p) { var o = p * 4; if (d[o + 3] >= 16 && dist(d, o, cor) <= TOL) perto++; });
    return { transparente: false, fundoLiso: perto / idx.length >= BORDA_LISA, cor: cor };
  }

  function dist(d, o, c) {
    var r = d[o] - c[0], gg = d[o + 1] - c[1], b = d[o + 2] - c[2];
    return Math.sqrt(r * r + gg * gg + b * b);
  }

  // Tira o fundo liso: pinta de transparente tudo que é da cor do fundo e se
  // liga à borda (o branco DENTRO do logo fica). Na beirada, cor-para-alfa:
  // o pixel meio fundo, meio logo vira logo semitransparente, sem o halo
  // branco que apareceria sobre o card escuro.
  function removerFundo(cv, cor) {
    var w = cv.width, h = cv.height, ctx = cv.getContext('2d');
    var im = ctx.getImageData(0, 0, w, h), d = im.data, N = w * h;
    var fundo = new Uint8Array(N), pilha = new Int32Array(N), topo = 0;
    bordaIdx(w, h).forEach(function (p) { if (!fundo[p] && dist(d, p * 4, cor) <= TOL) { fundo[p] = 1; pilha[topo++] = p; } });
    while (topo) {
      var p = pilha[--topo], x = p % w, y = (p / w) | 0;
      var viz = [x > 0 ? p - 1 : -1, x < w - 1 ? p + 1 : -1, y > 0 ? p - w : -1, y < h - 1 ? p + w : -1];
      for (var k = 0; k < 4; k++) {
        var q = viz[k];
        if (q >= 0 && !fundo[q] && dist(d, q * 4, cor) <= TOL) { fundo[q] = 1; pilha[topo++] = q; }
      }
    }
    for (var i = 0; i < N; i++) if (fundo[i]) d[i * 4 + 3] = 0;
    // Beirada: até 2 px do fundo removido.
    for (var volta = 0; volta < 2; volta++) {
      var anel = [];
      for (var j = 0; j < N; j++) {
        if (fundo[j]) continue;
        var jx = j % w, jy = (j / w) | 0;
        if ((jx > 0 && fundo[j - 1]) || (jx < w - 1 && fundo[j + 1]) || (jy > 0 && fundo[j - w]) || (jy < h - 1 && fundo[j + w])) anel.push(j);
      }
      anel.forEach(function (j) {
        var o = j * 4, a = 0;
        for (var c = 0; c < 3; c++) {
          var v = d[o + c], b = cor[c];
          var t = v > b ? (v - b) / (255 - b || 1) : v < b ? (b - v) / (b || 1) : 0;
          if (t > a) a = t;
        }
        a = Math.min(1, a);
        if (a > 0) for (var c2 = 0; c2 < 3; c2++) d[o + c2] = Math.max(0, Math.min(255, Math.round(cor[c2] + (d[o + c2] - cor[c2]) / a)));
        d[o + 3] = Math.round(Math.min(d[o + 3], a * 255));
        fundo[j] = 2; // a próxima volta anda um pixel pra dentro
      });
    }
    ctx.putImageData(im, 0, 0);
    return cv;
  }

  // Corta as margens vazias (transparentes) em volta do logo.
  function recortar(cv) {
    var w = cv.width, h = cv.height, d = cv.getContext('2d').getImageData(0, 0, w, h).data;
    var x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (var y = 0; y < h; y++) for (var x = 0; x < w; x++) {
      if (d[(y * w + x) * 4 + 3] > 10) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
    }
    if (x1 < 0) return cv; // ficou vazio: melhor a imagem como veio
    var c = canvas(x1 - x0 + 1, y1 - y0 + 1);
    c.getContext('2d').drawImage(cv, x0, y0, c.width, c.height, 0, 0, c.width, c.height);
    return c;
  }

  // Monta o PNG final. modo 'forma': inteiro, centrado, sobra transparente.
  // modo 'foto': preenche o quadrado de cantos arredondados. zoom ≥ 1;
  // dx/dy deslocam a partir do centro (em px do quadrado de 512).
  function compor(src, modo, zoom, dx, dy) {
    var c = canvas(LADO, LADO), x = c.getContext('2d');
    x.imageSmoothingQuality = 'high';
    var z = zoom || 1, w, h, px, py;
    if (modo === 'foto') {
      var k = Math.max(LADO / src.width, LADO / src.height) * z;
      w = src.width * k; h = src.height * k;
      px = Math.min(0, Math.max(LADO - w, (LADO - w) / 2 + (dx || 0)));
      py = Math.min(0, Math.max(LADO - h, (LADO - h) / 2 + (dy || 0)));
      var r = LADO * RAIO;
      x.beginPath();
      x.moveTo(r, 0); x.arcTo(LADO, 0, LADO, LADO, r); x.arcTo(LADO, LADO, 0, LADO, r); x.arcTo(0, LADO, 0, 0, r); x.arcTo(0, 0, LADO, 0, r);
      x.closePath(); x.clip();
      x.fillStyle = '#fff'; x.fillRect(0, 0, LADO, LADO);
    } else {
      var util = LADO - 2 * FOLGA, k2 = Math.min(util / src.width, util / src.height) * z;
      w = src.width * k2; h = src.height * k2;
      px = (LADO - w) / 2 + (dx || 0); py = (LADO - h) / 2 + (dy || 0);
    }
    x.drawImage(src, px, py, w, h);
    return { canvas: c, dx: modo === 'foto' ? px - (LADO - w) / 2 : dx || 0, dy: modo === 'foto' ? py - (LADO - h) / 2 : dy || 0 };
  }

  // Do arquivo/imagem às fontes prontas pra compor: { forma, foto, fundoLiso,
  // transparente }. forma é null quando a imagem não tem fundo que dê pra tirar.
  function preparar(img) {
    var base = canvasDe(img, 1024), info = analisar(base);
    var forma = null;
    if (info.transparente) forma = recortar(base);
    else if (info.fundoLiso) {
      var copia = canvas(base.width, base.height);
      copia.getContext('2d').drawImage(base, 0, 0);
      forma = recortar(removerFundo(copia, info.cor));
    }
    return { forma: forma, foto: base, fundoLiso: info.fundoLiso, transparente: info.transparente };
  }

  g.LoovLogoProcessa = { LADO: LADO, preparar: preparar, compor: compor, analisar: analisar, removerFundo: removerFundo, recortar: recortar };
})(window);
