import 'photo_file.dart';

const faceSteps = ['front', 'left', 'right', 'blink', 'smile'];
const facePrompts = [
  'Посмотрите прямо в камеру. Держите лицо целиком внутри рамки.',
  'Слегка поверните голову налево, чтобы оба глаза оставались видны.',
  'Слегка поверните голову направо, чтобы оба глаза оставались видны.',
  'Посмотрите прямо в камеру и моргните.',
  'Посмотрите прямо в камеру и улыбнитесь.',
];

class FaceSequence {
  final List<PhotoFile> photos;
  FaceSequence(this.photos);
}
