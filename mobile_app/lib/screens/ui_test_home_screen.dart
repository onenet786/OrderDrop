import 'package:flutter/material.dart';

class UiTestHomeScreen extends StatefulWidget {
  const UiTestHomeScreen({super.key});

  @override
  State<UiTestHomeScreen> createState() => _UiTestHomeScreenState();
}

class _UiTestHomeScreenState extends State<UiTestHomeScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F2F2),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Home',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.black87),
          onPressed: () {},
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.language, color: Color(0xFF1652A0)),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Welcome',
                style: TextStyle(fontSize: 20, color: Colors.black87),
              ),
              const SizedBox(height: 2),
              const Text(
                'Aqeel Ur Rehman',
                style: TextStyle(
                  fontSize: 46,
                  height: 0.95,
                  letterSpacing: -1.2,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              _buildMeterCard(),
              const SizedBox(height: 14),
              _buildPromoCard(),
              const SizedBox(height: 14),
              const Center(
                child: Icon(Icons.circle, size: 11, color: Colors.black45),
              ),
              const SizedBox(height: 12),
              _buildBillCard(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF15C7CE),
        unselectedItemColor: Colors.black54,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.pie_chart), label: 'Smart View'),
          BottomNavigationBarItem(icon: Icon(Icons.support_agent), label: 'Services'),
          BottomNavigationBarItem(icon: Icon(Icons.warning_amber), label: 'Complaints'),
        ],
      ),
    );
  }

  Widget _buildMeterCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF1555A5), Color(0xFF09346D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AQEEL UL REHMAN  S/O\nCH ALLAH BAKSH',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 20,
              height: 1.1,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Ref No.: 16113160813534',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          SizedBox(height: 4),
          Text(
            'REHMAN GARDEN',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'DOMESTIC',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromoCard() {
    return Container(
      height: 180,
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        gradient: const LinearGradient(
          colors: [Color(0xFF013D92), Color(0xFF1C66CC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Unlock',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'SMART FEATURES',
            style: TextStyle(
              color: Color(0xFFFFE13B),
              fontSize: 30,
              fontWeight: FontWeight.w800,
              height: 0.9,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Through Smart Meter',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          Spacer(),
          Align(
            alignment: Alignment.bottomCenter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFFFFD534),
                borderRadius: BorderRadius.all(Radius.circular(24)),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 26, vertical: 10),
                child: Text(
                  'APPLY NOW',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Bill',
                      style: TextStyle(fontSize: 18, color: Colors.black87),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Rs.19,452',
                      style: TextStyle(
                        fontSize: 48,
                        height: 0.95,
                        letterSpacing: -1.0,
                        color: Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '* View',
                      style: TextStyle(fontSize: 16, color: Color(0xFF0C4994)),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bill Status',
                    style: TextStyle(fontSize: 16, color: Colors.black87),
                  ),
                  Text(
                    'Un Paid',
                    style: TextStyle(
                      fontSize: 26,
                      color: Color(0xFF9E1515),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'Due date: 29 Jan 26',
                    style: TextStyle(fontSize: 16, color: Colors.black87),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'If already Paid. Please allow 3 days for processing.',
            style: TextStyle(
              color: Color(0xFF9E1515),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1652A0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () {},
              child: const Text(
                'Pay Now',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
