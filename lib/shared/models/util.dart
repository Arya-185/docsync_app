/// Coerce a dynamic JSON value to int (handles int, double, numeric string).
int asInt(dynamic v) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}
