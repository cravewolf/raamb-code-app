import 'dart:async';
import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:raamb_app/chat/ChatContent/chat_message.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:raamb_app/map/driver_map.dart';
import 'package:raamb_app/profile/profile_overview.dart';
import '../main.dart';
import '../service/mongo_service.dart';
import '../utils/location.dart';
import '../service/socket_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:developer' as developer;
import 'package:provider/provider.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import '../profile/profile_edit.dart';
import '../auth/login_page.dart';
import '../chat/ChatList/chat_list.dart';
import '../transaction/transaction_list.dart';
import '../drawer/favorites.dart';
import '../drawer/settings.dart';
import '../drawer/help_center.dart';
import '../drawer/terms_and_conditions.dart';
import 'package:intl/intl.dart';
import '../chat/chattest.dart';
import '../chat/ChatList/chatnew.dart';

class MechanicPage extends StatefulWidget {
  final String sessionId;
  final List<String> selectedVehicleTypes;

  MechanicPage({required this.sessionId, required this.selectedVehicleTypes});

  @override
  _MechanicPageState createState() => _MechanicPageState();
}

class _MechanicPageState extends State<MechanicPage> {
  LocationData? _locationData;
  Location _location = Location();
  String? _locationName;
  Timer? _timer;
  String? user;
  List<Map<String, dynamic>> driverUsers = [];
  List<Map<String, dynamic>> filteredDriverUsers = [];
  final SocketService socketService = SocketService();
  int _selectedIndex = 0;
   List<dynamic> bookingsList = [];
   List<Map<String, dynamic>> filteredBookingsList = [];
    String firstName = '';
    String email = '';
String lastName = '';
bool isLoading = false;
  bool isBookingConfirmed = false;
final StreamController<List<dynamic>> _bookingsStreamController = StreamController<List<dynamic>>();


   bool isResponseSent = false;
   
  

  // Add this variable for the selected tab index

  TextEditingController searchController = TextEditingController();

  

  @override
  void initState() {
    super.initState();
    _getLocation();
    _startLocationTimer();
    updateUserStatus(widget.sessionId, true);
    _loadUserData();
    filteredBookingsList = List.from(bookingsList);
    
    
    
    socketService.startSocketConnection();
    
    
    socketService.socket?.on("mechanicLocationUpdate", (data) {
      print('socketdata mechanic');
      print(data);
      updateDriverLocation(data);
    });


    

    socketService.socket?.on("mechanicUserStatusUpdate", (data) {
      print('socketdata mechanic status');
      print(data);
      updateDriverStatus(data);
      
    });
    socketService.socket?.on('bookingsData', (data) {
      print('gettingbook');
      setState(() {
        _bookingsStreamController.add(data);

        bookingsList = data;
      });
    });
    
  }

  @override
  void dispose() {
    _timer?.cancel();
    searchController.dispose();
 _bookingsStreamController.close();
    socketService.closeConnection();
    super.dispose();
  }

  void _startLocationTimer() {
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _getLocation();
    });
  }

  Future<void> _getLocation() async {
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        // Location services are not enabled, handle it accordingly
        return;
      }
    }

    permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        // Location permission not granted, handle it accordingly
        return;
      }
    }

    LocationData locationData = await _location.getLocation();
    List<geocoding.Placemark> placemarks =
        await geocoding.placemarkFromCoordinates(
      locationData.latitude!,
      locationData.longitude!,
    );
    if (placemarks.isNotEmpty) {
      geocoding.Placemark placemark = placemarks[0];
      String? address = placemark.thoroughfare;
      String? city = placemark.locality;
      String locationName = (address != null && city != null)
          ? '$address, $city'
          : (address ?? city ?? 'Unknown Location');
      setState(() {
        _locationData = locationData;
        _locationName = locationName;
      });

      
      updateLocation(widget.sessionId, locationData.latitude!,
          locationData.longitude!, locationName, city ?? '');
      updateUserStatus(widget.sessionId, true);
    }
  }

  void updateLocation(
    String sessionId,
    double latitude,
    double longitude,
    String locationName,
    String city,
  ) async {
    await updateLocationInDb(
      sessionId,
      latitude,
      longitude,
      locationName,
      city,
    );

    final Map<String, dynamic> locationUpdate = {
      'userId': sessionId,
      'location': {
        'latitude': latitude,
        'longitude': longitude,
        'address': locationName,
        'city': city,
      },
    };

    print("emit");
    socketService.socket?.emit("mechanicLocationUpdate", locationUpdate);
  }

  void updateUserStatus(String userId, bool isLogged) async {
    await updateUserStatusInDb(userId, isLogged);

    final Map<String, dynamic> userStatusUpdate = {
      'userId': userId,
      'isLogged': isLogged,
      'role': 'Mechanic',
    };
    socketService.socket?.emit("mechanicUserStatusUpdate", userStatusUpdate);
  }

void setupBookingsListener() {
  socketService.socket?.on('bookingsData', (data) {
    print('Receiving bookings data');
    setState(() {
      bookingsList = data; // Update bookingsList with the new data
    });
  });
}

  

 
  void _filterBookings(String query) {
    
  List<Map<String, dynamic>> tempFilteredList = [];
  if (query.isNotEmpty) {
    tempFilteredList = bookingsList
        .where((booking) {
          return booking['mechanicId'].toString().toLowerCase().contains(query.toLowerCase()) ||
                 booking['userId'].toString().toLowerCase().contains(query.toLowerCase()) ||
                 booking['bookingTime'].toString().toLowerCase().contains(query.toLowerCase());
        })
        .toList()
        .cast<Map<String, dynamic>>(); // Cast to the correct type
  } else {
    tempFilteredList = List<Map<String, dynamic>>.from(bookingsList); // If the query is empty, display all bookings
  }

  setState(() {
    filteredBookingsList = tempFilteredList;
  });
}


  void updateDriverLocation(Map<String, dynamic> data) {
    final String userId = data['userId'];
    final Map<String, dynamic>? location = data['location'];

    if (userId != null && location != null) {
      for (int i = 0; i < driverUsers.length; i++) {
        if (driverUsers[i]['_id'] == userId) {
          setState(() {
            driverUsers[i]['location'] = location;
            filteredDriverUsers = List.from(driverUsers);
          });
          // sortDriverUsers();
          break;
        }
      }
    }
  }

  void updateDriverStatus(Map<String, dynamic> data) {
    developer.log(data.toString(), name: 'userdata');
    print(data);
    print("mechanicdatastatus");
    final String userId = data['userId'];
    final bool isLogged = data['isLogged'];
    if (userId != null) {
      for (int i = 0; i < driverUsers.length; i++) {
        if (driverUsers[i]['_id'] == userId) {
          setState(() {
            driverUsers[i]['isLogged'] = isLogged;
            filteredDriverUsers = List.from(
                driverUsers.where((user) => user['isLogged'] == true));
          });
          // sortDriverUsers();
          break;
        }
      }
    }
  }

  void callUser(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Error'),
          content: Text('Failed to make the phone call.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _handleLogout() async {
  try {
   
    // Navigate to the login page
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (context) => LoginPage(), // Replace with your login page widget
    ));
  } catch (error) {
    // Handle any errors here
    print('Logout error: $error');
  }
}


void _confirmLogout(BuildContext context) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(
          'Confirm Logout',
         // Set title color to blue
        ),
        content: Text(
          'Do you really want to log out?',
           // Set content color to blue
        ),
        actions: <Widget>[
          TextButton(
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.blue), // Set button text color to blue
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: Text(
              'Log Out',
              style: TextStyle(color: Colors.blue), // Set button text color to blue
            ),
            onPressed: () {
              Navigator.of(context).pop();
              _handleLogout();
            },
          ),
        ],
      );
    },
  );
}



  

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

  
    if (index == 1) {
    
      _showProfile(widget.sessionId); // Replace _yourUserId with the user's ID
    }
  }

  void _showProfile(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileOverview(sessionId: userId),
      ),
    );
  }
  Widget _customButton(BuildContext context, String label, Color color, IconData icon, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.white),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        primary: color,
        onPrimary: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      ),
    );
  }

  

  Future<void> _loadUserData() async {
    final loginSession = Provider.of<LoginSession>(context, listen: false);
    final sessionId = loginSession.getUserId(); // Get the session ID from LoginSession provider

    try {
      final userData = await getUserData(sessionId); // Fetch user data
      if (userData != null && mounted) {
        setState(() {
          firstName = userData['firstName'];
          lastName = userData['lastName'];
          email = userData['email'];
        });
      }
    } catch (error) {
      // Handle any errors here
      print('Error fetching user data: $error');
    }
  }

void _markBookingAsComplete(String bookingId, String mechanicId) {
  if (socketService.socket == null) {
    print('Socket is not connected.');
    return;
  }

  var completionData = {
    'bookingId': bookingId,
    'userId': widget.sessionId,
    'mechanicId': mechanicId,
    'action': 'Completed'
  };

  socketService.socket?.emit('markBookingComplete', completionData);

  // Delete the booking once it's marked as complete
  deleteBooking(bookingId);
}


  void deleteBooking(String bookingId) {
  socketService.socket?.emit('deleteBooking', {bookingId});
  setState(() {
    bookingsList.removeWhere((b) => b['_id'] == bookingId);
  });
}





 
 

  void _showBookingDetailsPanel(BuildContext context, dynamic booking, String mechanicId) {
    bool localIsBookingConfirmed = false;
    final panelController = PanelController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
          return SlidingUpPanel(
        controller: panelController,
        minHeight: MediaQuery.of(context).size.height * .9,
        panelBuilder: (scrollController) => _buildPanel(
              scrollController, 
              booking, 
              panelController, 
              localIsBookingConfirmed,
              setModalState,
              mechanicId
       
      ),
          );
        },
      );
    },
  );
}


  Widget _buildPanel(ScrollController scrollController, dynamic booking, PanelController panelController, bool isConfirmed, StateSetter setModalState, String mechanicId) {
    
  final userLocation = LatLng(
    booking['userLocation']['latitude'],
    booking['userLocation']['longitude'],
  );

  final double distanceInMeters = calculateDistance(
    _locationData?.latitude,
    _locationData?.longitude,
    userLocation.latitude,
    userLocation.longitude,
  );
  final double distanceInKilometers = distanceInMeters / 1000;
  final bookingTimeFormatted = DateFormat.yMMMd().add_jm().format(DateTime.parse(booking['bookingTime']));

  return Stack(
    children: [
      FlutterMap(
        options: MapOptions(
          center: userLocation,
          zoom: 15.0,
        ),
        children: [
          TileLayer(
            urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
            subdomains: ['a', 'b', 'c'],
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: userLocation,
                builder: (ctx) => Icon(Icons.location_pin, color: Colors.red, size: 30),
              ),
            ],
          ),
        ],
      ),
      Positioned(
        top: 20,
        right: 20,
        left: 20,
        child: Material(
          elevation: 10,
          borderRadius: BorderRadius.circular(25),
          child: Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95), // Slightly transparent white
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.blueGrey.withOpacity(0.3),
                  blurRadius: 15,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Booking Details',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.deepPurple),
                ),
                SizedBox(height: 12),
                Divider(thickness: 2),
                SizedBox(height: 10),
                Text('User: ${booking['userDetails']['firstName']} ${booking['userDetails']['lastName']}', style: TextStyle(fontSize: 18, color: Colors.black87)),
                SizedBox(height: 8),
                Text('Booking Time: $bookingTimeFormatted', style: TextStyle(fontSize: 18, color: Colors.black87)),
                SizedBox(height: 8),
                Text(
                  'Distance: ${distanceInKilometers.toStringAsFixed(3)} km', 
                  style: TextStyle(fontSize: 18, color: Colors.black87)
                ),
                SizedBox(height: 15),
Row(
  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
  children: [
    _buildActionButton(
      'Accept',
      Icons.check_circle_outline,
      Colors.green.shade400,
      () {
        if (!isBookingConfirmed) {
          setModalState(() {
            isBookingConfirmed = true;
          });
          _handleResponse(booking['_id'], 'Accept', panelController, context, setModalState, mechanicId);
        }
      },
      isBookingConfirmed
    ),
   _buildActionButton(
  'Decline',
  Icons.remove_circle_outline,
  Colors.red.shade400,
  () {
    if (!isBookingConfirmed) {
      _handleResponse(booking['_id'], 'Decline', panelController, context, setModalState, mechanicId);
    }
  },
  isBookingConfirmed
),
  ],
),
    ],
    ),
        ),
   ) 
    )
    ]
    );
    
  }
  void showDeclinePanel(BuildContext context, String bookingId, String mechanicId) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(25),
          topRight: Radius.circular(25),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Text(
            'Booking Declined',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
          SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cancel_outlined, color: Colors.red, size: 28),
              SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Booking ID: $bookingId has been declined.',
                  style: TextStyle(fontSize: 16, color: Colors.black54),
                ),
              ),
            ],
          ),
          SizedBox(height: 30),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(); // Closes the current screen or dialog
            },
            child: Text('Close'),
            style: ElevatedButton.styleFrom(
              primary: Colors.deepPurple,
              onPrimary: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 50, vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
          ),
          SizedBox(height: 20),
        ],
      ),
    ),
  );
}


void showConfirmationPanel(BuildContext context, String bookingId, String mechanicId) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(25),
          topRight: Radius.circular(25),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Text(
            'Booking Accepted',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
          SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green, size: 28),
              SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Successfully accepted booking ID: $bookingId',
                  style: TextStyle(fontSize: 16, color: Colors.black54),
                ),
              ),
            ],
          ),
          SizedBox(height: 30),
          ElevatedButton(
            onPressed: () {
              _markBookingAsComplete(bookingId, mechanicId);
              Navigator.of(context).pop(); // This closes the current screen or dialog
            },
            child: Text('Finish'),
            style: ElevatedButton.styleFrom(
              primary: Colors.deepPurple,
              onPrimary: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 50, vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
          ),
          SizedBox(height: 20),
        ],
      ),
    ),
  );
}




Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback? onPressed, bool isDisabled) {
  return ElevatedButton.icon(
    onPressed: isDisabled ? null : onPressed,
    icon: Icon(icon, size: 24),
    label: Text(label),
    style: ElevatedButton.styleFrom(
      primary: color,
      onPrimary: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(35)),
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    ),
  );
}

  Widget showLoadingPanel() {
    return Center(child: CircularProgressIndicator());
  }

 void _handleResponse(String bookingId, String response, PanelController panelController, BuildContext context, StateSetter setModalState, String mechanicId) {
  setModalState(() {
    isLoading = true;
  });

  var emitEvent = (String event) {
    socketService.socket?.emit(event, {bookingId});
  };

  if (response == 'Accept') {
    emitEvent('acceptBooking');
    setModalState(() {
      isLoading = false;
      isBookingConfirmed = true;
    });
    showConfirmationPanel(context, bookingId, mechanicId);
  } else if (response == 'Decline') {
    emitEvent('declineBooking');
    deleteBooking(bookingId); // Delete the booking on decline
    setModalState(() {
      isLoading = false;
    });
    showDeclinePanel(context, bookingId, mechanicId);
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Response Sent: $response'))
  );

  panelController.close();
}




  


void _handleAccept(String bookingId) {
  socketService.socket?.emit('acceptBooking', bookingId);
  // Implement acceptance logic
}

void _handleDecline(String bookingId) {
  socketService.socket?.emit('declineBooking', bookingId);
  // Implement decline logic
}
Widget _buildDrawerItem(IconData icon, String title, VoidCallback onTap) {
  return ListTile(
    leading: Icon(icon, color: Colors.grey), // Custom icon color
    title: Text(title),
    onTap: onTap,
  );
}




  @override
  Widget build(BuildContext context) {
    var displayName = '${firstName ?? 'Your'} ${lastName ?? 'Name'}';
    var displayEmail = '${email?? ''}';
    

    return DefaultTabController(
  length: 4, // Number of tabs
  child: Scaffold(
    appBar: AppBar(
      title: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Text(
            _locationName ?? 'Location Unknown',
            style: TextStyle(
              fontSize: 20.0,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'Bookings',
            style: TextStyle(
              fontSize: 16.0,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
      centerTitle: true,
      leading: Builder(
        builder: (BuildContext context) {
          return IconButton(
            icon: Icon(Icons.menu),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          );
        },
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.refresh),
          onPressed: () {
            // Refresh action
            socketService.socket?.emit('getBookings');
          },
        ),
       IconButton(
      icon: Icon(Icons.email_outlined, size: 25),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => RecentMessagesScreen(sessionId: widget.sessionId,)), // Navigate to MessageListScreen
        );
      },
    ),
      ],
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue[800]?? Colors.blue, Colors.blue[900]?? Colors.blue], // Dark blue gradient
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      drawer:Drawer(
  child: Column(
    children: [
      Expanded(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
             UserAccountsDrawerHeader(
              accountName: Text(displayName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              accountEmail: Text(displayEmail ?? 'Unknown', style: TextStyle(fontSize: 16)),
              // Uncomment and update the following line to add a profile image
              // currentAccountPicture: CircleAvatar(
              //   backgroundImage: NetworkImage(userProfileImage),
              //   backgroundColor: Colors.white,
              // ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.blue[700] ?? Colors.blue, // Providing a fallback non-nullable color
        Colors.blue[300] ?? Colors.blueAccent, // Fallback non-nullable color
          ]
          ),
              ),
            ),
            _buildDrawerItem(Icons.account_circle, 'Profile', () {
              Navigator.pop(context); // Close drawer before navigating
              _showProfile(widget.sessionId);
            }),
            _buildDrawerItem(Icons.history, 'Transactions', () {
              Navigator.pop(context); // Close drawer before navigating
              // Navigate to TransactionsPage
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TransactionsPage(bookingId: widget.sessionId),
                ),
              );
            }),
            Divider(), // Simpler divider
            _buildDrawerItem(Icons.settings, 'Settings', () {
              // Navigate to SettingsPage
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => SettingsPage()),
              );
            }),
            _buildDrawerItem(Icons.help, 'Help Center', () {
              // Navigate to HelpCenterPage
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => HelpCenterPage()),
              );
            }),
            _buildDrawerItem(Icons.description, 'Terms and Conditions', () {
              Navigator.pop(context); // Close drawer before navigating
              // Navigate to TermsAndConditionsPage
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => TermsAndConditionsPage()),
              );
            }),
          ],
        ),
      ),
      ListTile(
        leading: Icon(Icons.exit_to_app), // Icon for "Log-Out"
        title: Text('Log-Out'),
        onTap: () {
          Navigator.pop(context); // Close drawer before logout
          _confirmLogout(context); // Your logout logic
        },
      ),
    ],
  ),
),

          body: Column(
      children: [
        Expanded(
          child: StreamBuilder<List<dynamic>>(
            stream: _bookingsStreamController.stream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              if (snapshot.data?.isEmpty ?? true) {
                return Center(child: Text('No bookings available', style: TextStyle(fontSize: 17, color: Colors.grey[600])));
              }

              List<dynamic> bookingsList = snapshot.data ?? [];

              return ListView.builder(
                itemCount: bookingsList.length,
                itemBuilder: (context, index) {
                  final booking = bookingsList[index];
                  final bookingTime = DateFormat.yMMMd().add_jm().format(DateTime.parse(booking['bookingTime']));
                  final userName = '${booking['userDetails']['firstName']} ${booking['userDetails']['lastName']}';

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                    child: Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 6,
                      child: Padding(
                        padding: const EdgeInsets.all(18.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Booking Time: $bookingTime',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: Colors.green),
                            ),
                            SizedBox(height: 10),
                            Text(
                              'User: $userName',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.red.shade700),
                            ),
                            SizedBox(height: 20),
                            Divider(color: Colors.red[300]),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _customButton(
                                  context,
                                  'Chat Messages',
                                  Colors.red.shade700,
                                  Icons.message,
                                  () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) => ChatMessagesTest(
                                          sessionId: widget.sessionId,
                                          user: booking['userId'],
                                          firstName: booking['userDetails']['firstName'],
                                          lastName: booking['userDetails']['lastName'],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                _customButton(
                                  context,
                                  'View Details',
                                  Colors.red.shade600,
                                  Icons.info_outline,
                                  () => _showBookingDetailsPanel(context, booking, booking['userId']),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  )
  );
  
}
}