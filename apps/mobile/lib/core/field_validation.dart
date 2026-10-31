String? textLengthProblem(String value, int min, int max, String label) {
  final length = value.trim().length;
  if (length < min)
    return '«$label»: нужно не менее $min символов. Сейчас $length. Добавьте ещё ${min - length}.';
  if (value.length > max)
    return '«$label»: допускается не более $max символов. Сейчас ${value.length}. Уберите ${value.length - max}.';
  return null;
}
