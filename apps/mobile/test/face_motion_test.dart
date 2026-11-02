import 'package:flutter_test/flutter_test.dart';
import '../lib/core/face_motion.dart';

Map<String, dynamic> face(
        {double yaw = 0,
        double blink = .05,
        double smile = .1,
        int faces = 1}) =>
    {
      'faces': faces,
      'yaw': yaw,
      'centerX': .5,
      'centerY': .5,
      'width': .4,
      'height': .6,
      'blinkLeft': blink,
      'blinkRight': blink,
      'smile': smile
    };
bool hold(FaceMotion m, Map<String, dynamic> frame, int start) {
  var captured = false;
  for (var i = 0; i < 5; i++)
    captured = m.observe(frame, start + i * 100) || captured;
  return captured;
}

void main() {
  test('static face cannot advance through head turns merely by waiting', () {
    final m = FaceMotion();
    expect(hold(m, face(), 0), true);
    m.advance(400);
    expect(hold(m, face(), 2000), false);
    expect(m.step, 1);
  });
  test(
      'only correct stable left/right positions advance; multiple faces reset the hold',
      () {
    final m = FaceMotion();
    expect(hold(m, face(), 0), true);
    m.advance(400);
    expect(hold(m, face(yaw: -.2), 1200), false);
    expect(hold(m, face(yaw: .2, faces: 2), 2000), false);
    expect(hold(m, face(yaw: .2), 3000), true);
    m.advance(3400);
    expect(hold(m, face(yaw: .2), 4200), false);
    expect(hold(m, face(yaw: -.2), 5000), true);
  });
  test(
      'blink requires open, both closed, then reopened eyes; smile requires expression change',
      () {
    final m = FaceMotion();
    expect(hold(m, face(), 0), true);
    m.advance(400);
    expect(hold(m, face(yaw: .2), 1200), true);
    m.advance(1600);
    expect(hold(m, face(yaw: -.2), 2400), true);
    m.advance(2800);
    expect(hold(m, face(blink: .9), 3600), false);
    expect(hold(m, face(), 4200), false);
    expect(m.observe(face(blink: .9), 4800), false);
    expect(m.observe(face(), 4900), false);
    expect(m.observe(face(), 5000), true);
    m.advance(5000);
    expect(hold(m, face(), 5800), false);
    expect(hold(m, face(smile: .8), 6500), true);
    m.advance(6900);
    expect(m.finished, true);
  });
  test('wink, off-frame face and isolated unstable readings do not capture',
      () {
    final m = FaceMotion();
    expect(m.observe(face(), 0), false);
    expect(m.observe({...face(), 'centerX': .99}, 100), false);
    expect(m.observe(face(), 200), false);
    expect(m.observe(face(faces: 0), 300), false);
    expect(m.observe(face(), 400), false);
    expect(m.step, 0);
  });
}
