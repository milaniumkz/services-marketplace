import 'photo_file.dart';

const faceSteps = ['front', 'left', 'right', 'blink', 'smile'];
const facePrompts = [
  'Смотрите прямо, без улыбки.',
  'Немного поверните голову налево.',
  'Поверните голову направо.',
  'Посмотрите прямо и моргните.',
  'Улыбнитесь.',
];

class FaceSequence {
  final List<PhotoFile> photos;
  FaceSequence(this.photos);
}
