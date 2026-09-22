import 'package:hive/hive.dart';

@HiveType(typeId: 9)
class Workspace extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final int colorValue;

  @HiveField(3)
  final int iconCodePoint;

  @HiveField(4)
  final int position;

  @HiveField(5)
  final bool isDefault;

  const Workspace({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.iconCodePoint,
    required this.position,
    this.isDefault = false,
  });

  Workspace copyWith({
    String? id,
    String? name,
    int? colorValue,
    int? iconCodePoint,
    int? position,
    bool? isDefault,
  }) {
    return Workspace(
      id: id ?? this.id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      iconCodePoint: iconCodePoint ?? this.iconCodePoint,
      position: position ?? this.position,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}

class WorkspaceAdapter extends TypeAdapter<Workspace> {
  @override
  final int typeId = 9;

  @override
  Workspace read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < count; i++) reader.readByte(): reader.read(),
    };
    return Workspace(
      id: fields[0] as String? ?? 'personal',
      name: fields[1] as String? ?? 'Personal',
      colorValue: fields[2] as int? ?? 0xFF2563EB,
      iconCodePoint: fields[3] as int? ?? 0xe491,
      position: fields[4] as int? ?? 0,
      isDefault: fields[5] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, Workspace obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.colorValue)
      ..writeByte(3)
      ..write(obj.iconCodePoint)
      ..writeByte(4)
      ..write(obj.position)
      ..writeByte(5)
      ..write(obj.isDefault);
  }
}
