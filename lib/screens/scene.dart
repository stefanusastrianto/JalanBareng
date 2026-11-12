// Ilustrasi kota buatan sendiri (SVG), dirender dengan flutter_svg.

String _sky(String a, String b) =>
    '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="$a"/><stop offset="1" stop-color="$b"/></linearGradient></defs><rect width="360" height="150" fill="url(#g)"/>';
String _sun(num x, num y, num r, [String c = '#FFC745']) =>
    '<circle cx="$x" cy="$y" r="${r + 8}" fill="$c" fill-opacity=".25"/><circle cx="$x" cy="$y" r="$r" fill="$c"/>';
String _cloud(num x, num y, [num s = 1, num o = .9]) =>
    '<g transform="translate($x $y) scale($s)" fill="#ffffff" fill-opacity="$o"><ellipse cx="0" cy="0" rx="22" ry="9"/><ellipse cx="14" cy="-6" rx="14" ry="10"/><ellipse cx="-10" cy="-4" rx="11" ry="8"/></g>';

String _mega(num x, num y, num s) {
  String sh(double k) {
    String f(num v) => (v * k).toStringAsFixed(1);
    return '<path d="M${f(-34)} ${f(6)} q0 -${f(16)} ${f(16)} -${f(16)} q4 -${f(14)} ${f(20)} -${f(12)} q12 -${f(10)} ${f(24)} ${f(2)} q${f(16)} 0 ${f(14)} ${f(14)} q-2 ${f(10)} -${f(14)} ${f(12)} z"/>';
  }

  return '<g transform="translate($x $y) scale($s)" fill="none" stroke-linejoin="round">'
      '<g fill="#E6F0FB" stroke="#24508F" stroke-width="2.2">${sh(1.25)}</g>'
      '<g stroke="#3F7FCB" stroke-width="2">${sh(1)}</g>'
      '<g stroke="#7FB0E6" stroke-width="2">${sh(.74)}</g>'
      '<g stroke="#B8D5F4" stroke-width="2">${sh(.5)}</g></g>';
}

String _train(num x, num y, [int len = 150, String c = '#E34B5B']) {
  final w = StringBuffer();
  for (var i = 0; i < len ~/ 22; i++) {
    w.write('<rect x="${8 + i * 22}" y="2.5" width="14" height="5" rx="1.5" fill="#9CC9E8"/>');
  }
  return '<g transform="translate($x $y)"><path d="M0 0h${len}q26 0 34 14H0z" fill="#ffffff" stroke="#C9D6D3"/><rect y="9" width="${len + 20}" height="2.5" fill="$c"/>$w</g>';
}

String _wrap(String inner) => '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 150">$inner</svg>';

String sceneSvg(String key) {
  switch (key) {
    case 'bandung':
      final rows = List.generate(4, (i) => '<path d="M-10 ${124 + i * 7}Q90 ${102 + i * 7} 180 ${120 + i * 7}T370 ${112 + i * 7}" fill="none" stroke="#3FA27B" stroke-width="2.4" stroke-dasharray="6 5" stroke-opacity=".7"/>').join();
      return _wrap(_sky('#BFE8FF', '#F1FBFF') + _sun(298, 38, 15) + _cloud(80, 32, .9) + _cloud(220, 24, .6) +
          '<path d="M0 104L60 76L104 58L170 56L218 72L280 66L360 92V150H0z" fill="#A9DCCB"/><path d="M0 116Q90 92 180 112T360 104V150H0z" fill="#5DBB93"/>' +
          rows + _train(26, 132, 170));
    case 'cirebon':
      return _wrap(_sky('#FFEBDD', '#FFF9F3') + _sun(62, 42, 14, '#FFB44A') + _mega(250, 46, 1) + _mega(150, 30, .55) +
          '<rect y="124" width="360" height="26" fill="#EBD6B4"/><g fill="#C9573F"><path d="M128 124V86l8-6V66l7-5V48l6-5 6 5v13l7 5v14l8 6v38z"/><path d="M232 124V86l-8-6V66l-7-5V48l-6-5-6 5v13l-7 5v14l-8 6v38z"/></g><g fill="#A9432F"><rect x="128" y="96" width="42" height="4"/><rect x="190" y="96" width="42" height="4"/><rect x="128" y="112" width="42" height="3"/><rect x="190" y="112" width="42" height="3"/></g>');
    case 'kuningan':
      return _wrap(_sky('#CFEEFF', '#F2FBFF') + _sun(300, 34, 13) + _cloud(70, 30, .8) +
          '<path d="M70 112L170 38q10-6 20 0L292 112z" fill="#86AFC0"/><path d="M162 46q18-10 36 0l-6 8q-12-6-24 0z" fill="#5E8796"/><path d="M0 108Q80 96 160 108T360 104V150H0z" fill="#B9E38E"/><path d="M0 122Q100 110 200 122T360 118V150H0z" fill="#8CCB6C"/><path d="M0 136Q110 126 220 136T360 132V150H0z" fill="#6CB45A"/><ellipse cx="78" cy="118" rx="44" ry="7" fill="#8ED6F2"/>');
    case 'solo':
      final kawung = List.generate(13, (i) => '<g transform="translate(${14 + i * 28} 139)" fill="#9A5F3A"><ellipse cx="0" cy="0" rx="3" ry="6"/><ellipse cx="0" cy="0" rx="6" ry="3"/><circle cx="0" cy="0" r="1.6" fill="#EAD2AE"/></g>').join();
      final cols = [136, 160, 196, 220].map((x) => '<rect x="$x" y="98" width="6" height="30"/>').join();
      return _wrap(_sky('#FFF2D2', '#FFFBF0') + _sun(296, 40, 14, '#FFB84A') + _cloud(90, 30, .7) +
          '<path d="M96 84L180 46L264 84z" fill="#9A5F3A"/><path d="M118 98L180 70L242 98z" fill="#B97B4D"/><rect x="128" y="98" width="104" height="30" fill="#F6E7CF"/><g fill="#7A4A2C">$cols</g><rect y="128" width="360" height="22" fill="#EAD2AE"/>' +
          kawung);
    case 'klaten':
    case 'jogja':
      final water = List.generate(3, (i) => '<path d="M0 ${122 + i * 9}H360" stroke="#CFEFF7" stroke-width="2"/>').join();
      return _wrap(_sky('#FFE6D2', '#FFF8F1') + _sun(80, 46, 16, '#FF9F4A') + _cloud(250, 30, .7) +
          '<g fill="#B77A59"><path d="M180 30l6 10h-12z"/><path d="M168 56h24l-4-16h-16z"/><path d="M160 82h40l-6-26h-28z"/><path d="M150 112h60l-8-30h-44z"/><path d="M108 112h34l-4-18h-8l-2-10h-6l-2 10h-8z"/><path d="M218 112h34l-4-18h-8l-2-10h-6l-2 10h-8z"/></g><rect y="112" width="360" height="38" fill="#9ED37A"/>' +
          water);
    case 'jakarta':
      final bld = [
        [20, 70], [48, 86], [250, 64], [284, 80], [318, 90]
      ].map((p) => '<rect x="${p[0]}" y="${p[1]}" width="24" height="${118 - p[1]}"/>').join();
      return _wrap(_sky('#D6EEFF', '#F4FAFF') + _sun(290, 40, 13) + _cloud(90, 34, .8) +
          '<path d="M174 34h12v84h-12z" fill="#F4F4F2" stroke="#C9D6D3"/><path d="M176 22q4-10 8 0l2 12h-12z" fill="#FFC745"/><path d="M150 118h60l-6-14h-48z" fill="#E7ECEB"/><g fill="#B8CFD9">$bld</g><rect y="118" width="360" height="32" fill="#CFE6D8"/>');
    case 'natal':
      final trees = [
        [60, 118], [96, 118], [252, 118], [292, 118]
      ].asMap().entries.map((e) => '<path d="M${e.value[0]} ${e.value[1] - 44}l14 22h-8l12 22h-36l12-22h-8z" fill="${e.key.isOdd ? '#3BA272' : '#2E8C62'}"/>').join();
      const lights = ['#E04F5F', '#FFC745', '#3E9FD8'];
      final dots = List.generate(14, (i) => '<circle cx="${20 + i * 24}" cy="${14 + (i % 3) * 5}" r="2.4" fill="${lights[i % 3]}"/>').join();
      return _wrap(_sky('#E2F6EF', '#FBFFFD') +
          '<path d="M300 20l4 10 11 1-8 7 3 11-10-6-10 6 3-11-8-7 11-1z" fill="#FFC745"/><path d="M0 118Q120 104 240 118T360 114V150H0z" fill="#CDEBD9"/><path d="M150 118V82l30-22 30 22v36z" fill="#ffffff" stroke="#D6E3DF"/><path d="M144 86l36-30 36 30" fill="none" stroke="#E04F5F" stroke-width="6" stroke-linejoin="round"/><path d="M180 28v26M172 36h16" stroke="#E04F5F" stroke-width="3"/><path d="M172 118v-18q8-8 16 0v18z" fill="#F2B880"/>' +
          trees +
          dots);
    case 'istirahat':
      return _wrap(_sky('#CFF0FF', '#F3FCFF') + _sun(280, 36, 14) + _cloud(120, 28, .7) +
          '<rect y="96" width="360" height="30" fill="#7ED3EA"/><path d="M0 122Q180 112 360 122V150H0z" fill="#F5E2B8"/><path d="M70 126q6-40 -4-70" fill="none" stroke="#8A5A3C" stroke-width="5"/><path d="M290 126q-8-38 4-66" fill="none" stroke="#8A5A3C" stroke-width="5"/><g fill="#3BA272"><path d="M66 56q-30 0-40 14q20-8 40-10z"/><path d="M66 56q30-4 42 10q-22-6-42-6z"/><path d="M66 56q-8-24 6-34q-2 18-2 32z"/><path d="M294 60q-30 0-40 14q20-8 40-10z"/><path d="M294 60q30-4 42 10q-22-6-42-6z"/></g><path d="M72 94Q180 128 288 98" fill="none" stroke="#F2704F" stroke-width="4"/>');
    case 'pulang':
      return _wrap(_sky('#FFD9C2', '#FFF4EC') + _sun(250, 92, 22, '#FF8A4A') +
          '<path d="M0 112Q90 100 180 110T360 106V150H0z" fill="#A6D88A"/>' +
          _train(40, 114, 220, '#3E9FD8') +
          '<rect y="132" width="360" height="18" fill="#8CC96E"/><path d="M0 138H360" stroke="#CFEFF7" stroke-width="1.5"/><path d="M0 144H360" stroke="#CFEFF7" stroke-width="1.5"/>');
    default:
      return _wrap(_sky('#D5F1F5', '#F6FDFC') + _sun(290, 38, 14) + _cloud(80, 30, .8) + _cloud(200, 22, .5) +
          '<path d="M0 104L80 72L150 92L230 64L360 98V150H0z" fill="#B5E0D2"/><path d="M0 120Q120 100 220 118T360 112V150H0z" fill="#73C49E"/>' +
          _train(60, 128, 140));
  }
}
