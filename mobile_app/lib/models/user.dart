class User {
  final int id;
  final String firstName;
  final String lastName;
  final String email;
  final String userType;
  final String? phone;
  final String? address;
  final String? dateOfBirth;
  final bool isGuest;

  User({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.userType,
    this.phone,
    this.address,
    this.dateOfBirth,
    this.isGuest = false,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    final rawIsGuest = json['is_guest'];
    final guestFromFlag =
        rawIsGuest == true || rawIsGuest == 1 || rawIsGuest == '1';
    final userType = json['user_type'] ?? 'customer';
    return User(
      id: json['id'],
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      email: json['email'] ?? '',
      userType: userType,
      phone: json['phone'],
      address: json['address'],
      dateOfBirth: json['date_of_birth'],
      isGuest: guestFromFlag || userType == 'guest',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'user_type': userType,
      'phone': phone,
      'address': address,
      'date_of_birth': dateOfBirth,
      'is_guest': isGuest,
    };
  }
}
