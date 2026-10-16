class AssignedProgram {
  final String id;
  final String name;
  final int count;
  final String? lastDate;

  AssignedProgram({
    required this.id,
    required this.name,
    required this.count,
    this.lastDate,
  });
}
