class Program {
  final String id;
  final String name;
  final String description;

  Program({
    required this.id,
    required this.name,
    required this.description,
  });

  factory Program.fromMap(Map<String, dynamic> map) {
    return Program(
      id: map['id'].toString(),
      name: map['name'] ?? '',
      description: map['description'] ?? '',
    );
  }
}
