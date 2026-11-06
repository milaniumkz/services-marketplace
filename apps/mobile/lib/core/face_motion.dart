/// Landmark/expression gates only. This is not a media anti-spoofing detector.
class FaceMotion {
  int step = 0;
  int _count = 0, _notBefore = 0;
  int? _since, _closedAt;
  String _blink = 'open';
  double _baseYaw = 0, _baseSmile = 0;
  String hint = '';
  bool get finished => step >= 5;
  void _resetHold() {
    _count = 0;
    _since = null;
  }

  bool observe(Map<String, dynamic> m, int now) {
    if (finished || now < _notBefore) return false;
    final values = [
      'yaw',
      'centerX',
      'centerY',
      'width',
      'height',
      'blinkLeft',
      'blinkRight',
      'smile'
    ];
    if (m['faces'] != 1 ||
        values.any((k) => m[k] is! num || !(m[k] as num).isFinite)) {
      _resetHold();
      _blink = 'open';
      _closedAt = null;
      hint = m['faces'] is num && m['faces'] > 1
          ? 'В кадре должен быть один человек.'
          : 'Расположите лицо целиком внутри рамки.';
      return false;
    }
    final yaw = (m['yaw'] as num).toDouble(),
        smile = (m['smile'] as num).toDouble();
    final left = (m['blinkLeft'] as num).toDouble(),
        right = (m['blinkRight'] as num).toDouble();
    final framed = m['centerX'] > .2 &&
        m['centerX'] < .8 &&
        m['centerY'] > .15 &&
        m['centerY'] < .85 &&
        m['width'] >= .18 &&
        m['width'] < .9 &&
        m['height'] >= .22 &&
        m['height'] < .96;
    if (!framed) {
      _resetHold();
      _blink = 'open';
      hint = 'Поместите лицо целиком в рамку и держите телефон ровно.';
      return false;
    }
    final delta = yaw - _baseYaw, eyesOpen = left < .28 && right < .28;
    bool valid;
    if (step == 0) {
      valid = yaw.abs() <= .16 && eyesOpen && smile < .4;
      hint = valid
          ? 'Замрите на мгновение…'
          : 'Смотрите прямо, расслабьте лицо и откройте глаза.';
    } else if (step == 1 || step == 2) {
      valid = (step == 1
              ? delta >= .10 && delta <= .40
              : delta <= -.10 && delta >= -.40) &&
          left < .48 &&
          right < .48;
      hint = valid
          ? 'Фиксируем положение…'
          : (step == 1
              ? 'Немного поверните голову налево.'
              : 'Немного поверните голову направо.');
    } else if (step == 3) {
      if (delta.abs() > .10) {
        _resetHold();
        _blink = 'open';
        hint = 'Верните голову прямо и моргните.';
        return false;
      }
      if (_closedAt != null && now - _closedAt! > 2200) {
        _blink = 'open';
        _closedAt = null;
      }
      if (_blink == 'open' && eyesOpen) _blink = 'close';
      if (_blink == 'close' && left > .42 && right > .42) {
        _blink = 'reopen';
        _closedAt = now;
        _resetHold();
      }
      valid = _blink == 'reopen' && eyesOpen;
      hint = valid
          ? 'Моргание зафиксировано…'
          : 'Закройте и снова откройте оба глаза.';
    } else {
      valid = delta.abs() <= .10 &&
          eyesOpen &&
          smile >= .38 &&
          smile - _baseSmile >= .12;
      hint = valid ? 'Улыбка зафиксирована…' : 'Смотрите прямо и улыбнитесь.';
    }
    if (!valid) {
      _resetHold();
      return false;
    }
    _since ??= now;
    _count++;
    final ready = _count >= (step >= 3 ? 2 : 3) &&
        now - _since! >=
            (step == 3
                ? 40
                : step == 4
                    ? 100
                    : 300);
    if (ready && step == 0) {
      _baseYaw = yaw;
      _baseSmile = smile;
    }
    return ready;
  }

  void advance(int now) {
    step++;
    _resetHold();
    _blink = 'open';
    _closedAt = null;
    _notBefore = step >= 3 ? now : now + 650;
    hint = '';
  }
}
