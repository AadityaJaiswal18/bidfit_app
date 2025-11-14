import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('expenses');
  runApp(const Root());
}

/// ROOT - reads theme pref and launches app
class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  bool _isDark = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final sp = await SharedPreferences.getInstance();
    final t = sp.getBool('isDark') ?? true;
    setState(() {
      _isDark = t;
      _loaded = true;
    });
  }

  Future<void> _toggleTheme() async {
    final sp = await SharedPreferences.getInstance();
    setState(() {
      _isDark = !_isDark;
    });
    await sp.setBool('isDark', _isDark);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    // Use ValueListenableBuilder for Hive box changes to automatically refresh the UI
    return ValueListenableBuilder(
      valueListenable: Hive.box('expenses').listenable(),
      builder: (context, box, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Expense Pro+',
          theme: _isDark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true),
          home: DashboardPage(isDark: _isDark, onToggleTheme: _toggleTheme),
        );
      },
    );
  }
}

/// DASHBOARD WITH ALL FEATURES
class DashboardPage extends StatefulWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;
  const DashboardPage({super.key, required this.isDark, required this.onToggleTheme});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with SingleTickerProviderStateMixin {
  final Box box = Hive.box('expenses');

  // form controllers
  final TextEditingController _titleCtr = TextEditingController();
  final TextEditingController _amountCtr = TextEditingController();
  String selectedCategory = "Food";
  DateTime selectedDate = DateTime.now();
  TimeOfDay selectedTime = TimeOfDay.now();

  // search + filter
  String searchQuery = '';
  String monthFilter = 'All';

  // categories
  final List<String> categories = [
    "Food",
    "Travel",
    "Shopping",
    "Bills",
    "Groceries",
    "Medicine",
    "Entertainment",
    "Fuel",
    "Recharge",
    "EMI",
    "Investment",
    "Other"
  ];

  // Colors for charts (more professional palette)
  final List<Color> chartColors = [
    Colors.deepOrange,
    Colors.teal,
    Colors.indigo,
    Colors.pink,
    Colors.purple,
    Colors.amber,
    Colors.cyan,
    Colors.green,
    Colors.redAccent,
    Colors.blueGrey,
    Colors.lime,
    Colors.brown
  ];

  // animation controller (for small UI polish)
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _animController.forward();
  }

  @override
  void dispose() {
    _titleCtr.dispose();
    _amountCtr.dispose();
    _animController.dispose();
    super.dispose();
  }

  // ---------- HELPERS ----------

  double totalAmount({String? month}) {
    double sum = 0;
    for (var v in box.values) {
      final m = Map.from(v);
      final amt = (m['amount'] ?? 0).toDouble();
      final d = DateTime.parse(m['date']);
      if (month == null || month == 'All' || _formatMonth(d) == month) sum += amt;
    }
    return sum;
  }

  double categoryTotal(String cat, {String? month}) {
    double sum = 0;
    for (var v in box.values) {
      final m = Map.from(v);
      final d = DateTime.parse(m['date']);
      final amt = (m['amount'] ?? 0).toDouble();
      if (m['category'] == cat && (month == null || month == 'All' || _formatMonth(d) == month)) sum += amt;
    }
    return sum;
  }

  List<String> availableMonths() {
    Set<String> s = {'All'};
    for (var v in box.values) {
      final d = DateTime.parse(Map.from(v)['date']);
      s.add(_formatMonth(d));
    }
    final list = s.toList();
    list.sort((a, b) {
      if (a == 'All') return -1;
      if (b == 'All') return 1;
      return b.compareTo(a); // descending (recent first)
    });
    return list;
  }

  String _formatMonth(DateTime d) {
    final y = d.year.toString();
    final m = d.month.toString().padLeft(2, '0');
    return '$y-$m'; // YYYY-MM
  }

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  // filtered list indices (applies monthFilter + searchQuery)
  List<int> filteredIndices() {
    List<int> idx = [];
    for (int i = 0; i < box.length; i++) {
      final m = Map.from(box.getAt(i));
      final d = DateTime.parse(m['date']);
      final monthOk = monthFilter == 'All' || _formatMonth(d) == monthFilter;
      final q = searchQuery.toLowerCase();
      final title = (m['title'] ?? '').toString().toLowerCase();
      final cat = (m['category'] ?? '').toString().toLowerCase();
      final searchOk = q.isEmpty || title.contains(q) || cat.contains(q);
      if (monthOk && searchOk) idx.add(i);
    }
    // Sort by date/time (descending)
    idx.sort((a, b) {
      final mA = Map.from(box.getAt(a));
      final mB = Map.from(box.getAt(b));
      DateTime dtA;
      DateTime dtB;
      try {
        dtA = DateTime.parse('${mA['date']} ${mA['time']}');
      } catch (_) {
        dtA = DateTime(0);
      }
      try {
        dtB = DateTime.parse('${mB['date']} ${mB['time']}');
      } catch (_) {
        dtB = DateTime(0);
      }
      return dtB.compareTo(dtA);
    });
    return idx;
  }

  // PIE chart sections
  List<PieChartSectionData> pieSectionsFor({String? month}) {
    List<PieChartSectionData> out = [];
    for (int i = 0; i < categories.length; i++) {
      final val = categoryTotal(categories[i], month: month);
      if (val <= 0) continue;
      out.add(PieChartSectionData(
        value: val,
        color: chartColors[i % chartColors.length],
        title: '',
        radius: 50,
      ));
    }
    if (out.isEmpty) {
      out.add(PieChartSectionData(value: 1, color: Colors.grey, title: ''));
    }
    return out;
  }

  // BAR chart data for selected month
  BarChartData barDataForMonth(String monthKey) {
    // monthKey format: 'YYYY-MM'
    final parts = monthKey.split('-');
    final y = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final lastDay = DateTime(y, m + 1, 0).day;
    List<double> sums = List.filled(lastDay + 1, 0.0); // 1-based idx

    for (var v in box.values) {
      final map = Map.from(v);
      final d = DateTime.parse(map['date']);
      if (d.year == y && d.month == m) sums[d.day] += (map['amount'] ?? 0).toDouble();
    }

    List<BarChartGroupData> groups = [];
    double maxAmount = sums.fold(0.0, (prev, element) => element > prev ? element : prev);

    for (int day = 1; day <= lastDay; day++) {
      groups.add(BarChartGroupData(
        x: day,
        barRods: [
          BarChartRodData(
            toY: sums[day],
            width: 8,
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(3), topRight: Radius.circular(3)),
            color: Colors.blueAccent, // Professional color
          )
        ],
      ));
    }

    return BarChartData(
      barGroups: groups,
      maxY: maxAmount * 1.1,
      titlesData: FlTitlesData(
        show: true,
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 20, getTitlesWidget: (v, meta) {
          final idx = v.toInt();
          final N = (lastDay / 7).ceil();
          if (idx == 1 || idx == lastDay || idx % N == 0) {
            return SideTitleWidget(axisSide: meta.axisSide, child: Text(idx.toString(), style: const TextStyle(fontSize: 10)));
          }
          return const SizedBox.shrink();
        })),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, interval: maxAmount <= 0 ? 1 : maxAmount / 5, getTitlesWidget: (value, meta) {
          if (value == 0) return const SizedBox.shrink();
          return Text(value.toStringAsFixed(0), style: const TextStyle(fontSize: 10));
        })),
      ),
      gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: maxAmount <= 0 ? 1 : maxAmount / 5, getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.3), strokeWidth: 0.5)),
      borderData: FlBorderData(show: false),
    );
  }

  // LINE chart data for last 7 days
  LineChartData lineDataForLast7Days() {
    Map<String, double> dailyExpenses = {};
    DateTime now = DateTime.now();

    // Initialize map for the last 7 days (including today)
    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      dailyExpenses[_formatDate(date)] = 0.0;
    }

    // Calculate expenses
    for (var v in box.values) {
      final map = Map.from(v);
      final dateString = map['date'];
      final formattedDate = dateString;

      if (dailyExpenses.containsKey(formattedDate)) {
        dailyExpenses[formattedDate] = (dailyExpenses[formattedDate]! + (map['amount'] ?? 0).toDouble());
      }
    }

    List<FlSpot> spots = [];
    List<String> sortedDates = dailyExpenses.keys.toList()..sort();

    // Assign index 0-6 for chart spots
    for (int i = 0; i < sortedDates.length; i++) {
      spots.add(FlSpot(i.toDouble(), dailyExpenses[sortedDates[i]]!));
    }

    double maxY = spots.isEmpty || spots.every((spot) => spot.y == 0)
        ? 100
        : spots.map((e) => e.y).reduce((a, b) => a > b ? a : b) * 1.2;

    double minY = spots.isEmpty || spots.every((spot) => spot.y == 0)
        ? 0
        : -5; // Small negative buffer

    return LineChartData(
      gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.3), strokeWidth: 0.5)),
      titlesData: FlTitlesData(
        show: true,
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 20, getTitlesWidget: (value, meta) {
          final dayIndex = value.toInt();
          if (dayIndex >= 0 && dayIndex < sortedDates.length) {
            final date = DateTime.parse(sortedDates[dayIndex]);
            // Show only the day (e.g., '14')
            return SideTitleWidget(axisSide: meta.axisSide, space: 4, child: Text(date.day.toString(), style: const TextStyle(fontSize: 10)));
          }
          return const SizedBox.shrink();
        })),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (value, meta) {
          if (value == 0 || value == maxY) return const SizedBox.shrink();
          return Text(value.toStringAsFixed(0), style: const TextStyle(fontSize: 10));
        })),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      minX: 0,
      maxX: 6,
      minY: minY,
      maxY: maxY,
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          barWidth: 4,
          color: Colors.deepOrangeAccent, // Professional color
          dotData: FlDotData(show: true, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 4, color: Colors.deepOrange, strokeColor: Colors.white, strokeWidth: 2)),
          belowBarData: BarAreaData(show: true, color: Colors.deepOrangeAccent.withOpacity(0.2)),
        ),
      ],
    );
  }


  // EXPORT CSV -> writes to documents directory
  Future<void> exportCSV() async {
    if (box.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No data to export')));
      return;
    }
    final header = 'Title,Amount,Category,Date,Time\n';
    final rows = <String>[];
    for (var v in box.values) {
      final m = Map.from(v);
      final t = m['title']?.toString().replaceAll(',', ' ') ?? '';
      final a = (m['amount'] ?? 0).toString();
      final c = m['category']?.toString().replaceAll(',', ' ') ?? '';
      final d = m['date'] ?? '';
      final ti = m['time'] ?? '';
      rows.add('$t,$a,$c,$d,$ti');
    }
    final csv = header + rows.join('\n');

    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'expenses_${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}${DateTime.now().day.toString().padLeft(2, '0')}.csv';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(csv);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported CSV to: ${file.path}')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Export failed')));
    }
  }

  // ADD / EDIT dialog
  void openDialog({int? index}) {
    final isEdit = index != null;
    if (isEdit) {
      final m = Map.from(box.getAt(index));
      _titleCtr.text = m['title'] ?? '';
      _amountCtr.text = (m['amount'] ?? '').toString();
      selectedCategory = m['category'] ?? categories.first;
      selectedDate = DateTime.parse(m['date']);
      final parts = (m['time'] ?? '00:00').split(':');
      selectedTime = TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
    } else {
      _titleCtr.clear();
      _amountCtr.clear();
      selectedCategory = categories.first;
      selectedDate = DateTime.now();
      selectedTime = TimeOfDay.now();
    }

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) { // Use StatefulBuilder to manage dialog-specific state
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Text(isEdit ? 'Edit Expense' : 'Add Expense', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ]),
                const SizedBox(height: 8),
                TextField(controller: _titleCtr, decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: _amountCtr, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount (₹)', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setDialogState(() => selectedCategory = v ?? categories.first),
                  decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Category'),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final pick = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                        if (pick != null) setDialogState(() => selectedDate = pick);
                      },
                      child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)), child: Row(children: [const Icon(Icons.calendar_month), const SizedBox(width: 8), Text('${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}')],)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final pick = await showTimePicker(context: context, initialTime: selectedTime);
                        if (pick != null) setDialogState(() => selectedTime = pick);
                      },
                      child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)), child: Row(children: [const Icon(Icons.access_time), const SizedBox(width: 8), Text('${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}')],)),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    final t = _titleCtr.text.trim();
                    final a = double.tryParse(_amountCtr.text.trim()) ?? 0.0;
                    if (t.isEmpty || a <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter valid title & amount')));
                      return;
                    }
                    final data = {
                      'title': t,
                      'amount': a,
                      'category': selectedCategory,
                      'date': _formatDate(selectedDate),
                      'time': '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                    };
                    if (isEdit) box.putAt(index!, data); // **UPDATE** function: Update existing expense at index
                    else box.add(data);
                    Navigator.pop(context);
                    setState(() {});
                  },
                  child: Text(isEdit ? 'Update' : 'Add'),
                )
              ]),
            ),
          );
        },
      ),
    ).then((_) {
      setState(() {});
    });
  }

  // glass card helper
  Widget glass({required Widget child, double? height}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: Container(height: height, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: widget.isDark ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.8), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(0.06))), child: child)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isTablet = w >= 700;
    final wide = w >= 900;
    final months = availableMonths();
    final pie = pieSectionsFor(month: monthFilter == 'All' ? null : monthFilter);
    final showBar = monthFilter != 'All';

    final indices = filteredIndices();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Pro+'),
        actions: [
          IconButton(onPressed: widget.onToggleTheme, icon: Icon(widget.isDark ? Icons.wb_sunny : Icons.nightlight_round)),
          IconButton(onPressed: exportCSV, icon: const Icon(Icons.download))
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(onPressed: () => openDialog(), child: const Icon(Icons.add)),
      body: Padding(
        padding: EdgeInsets.all(isTablet ? 20 : 12),
        child: Column(children: [
          // Header + Search + Filters (Animation)
          SizeTransition(
            sizeFactor: CurvedAnimation(parent: _animController, curve: Curves.easeOut),
            child: Column(children: [
              Row(children: [
                Expanded(child: glass(child: Row(children: [const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.pie_chart, color: Colors.deepOrange)), const SizedBox(width: 8), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Total Spent', style: TextStyle(color: Colors.grey)), const SizedBox(height: 6), Text('₹ ${totalAmount(month: monthFilter == 'All' ? null : monthFilter).toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))])]))),
                const SizedBox(width: 12),
                Expanded(child: glass(child: Row(children: [const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.category, color: Colors.teal)), const SizedBox(width: 8), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Categories', style: TextStyle(color: Colors.grey)), const SizedBox(height: 6), Text('${categories.length}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))])]))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Search by title or category', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                    onChanged: (v) => setState(() => searchQuery = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: monthFilter,
                    items: months.map((m) {
                      final label = m == 'All' ? 'All' : m.replaceFirst('-', ' / ');
                      return DropdownMenuItem(value: m, child: Text(label));
                    }).toList(),
                    onChanged: (v) => setState(() => monthFilter = v ?? 'All'),
                    decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Month'),
                  ),
                )
              ]),
            ]),
          ),
          const SizedBox(height: 12),

          // Charts + List
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Left Charts (Visible on Wide screens)
                if (wide)
                  Expanded(
                    flex: 1,
                    child: ListView(
                      children: [
                        // PIE CHART
                        glass(
                          height: 360,
                          child: Column(children: [
                            const Row(children: [Text('Spending by Category', style: TextStyle(fontWeight: FontWeight.bold)), const Spacer()]),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Row(children: [
                                Expanded(child: Center(child: PieChart(PieChartData(sections: pie, centerSpaceRadius: 60, sectionsSpace: 4, pieTouchData: PieTouchData(enabled: false))))),
                                const SizedBox(width: 8),
                                Expanded(child: ListView(padding: EdgeInsets.zero, children: categories.map((c) {
                                  final v = categoryTotal(c, month: monthFilter == 'All' ? null : monthFilter);
                                  if (v <= 0) return const SizedBox.shrink();
                                  final idx = categories.indexOf(c);
                                  return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [Container(width: 12, height: 12, decoration: BoxDecoration(color: chartColors[idx % chartColors.length], borderRadius: BorderRadius.circular(4))), const SizedBox(width: 8), Expanded(child: Text(c)), Text('₹ ${v.toStringAsFixed(2)}', style: TextStyle(color: Colors.grey.shade400))]));
                                }).toList())),
                              ]),
                            )
                          ]),
                        ),
                        const SizedBox(height: 12),

                        // BAR CHART (Daily for selected month)
                        if (showBar)
                          glass(
                            height: 260,
                            child: Column(children: [
                              Row(children: [Text('Daily Spending — ${monthFilter.replaceFirst('-', '/')}'), const Spacer()]),
                              const SizedBox(height: 8),
                              Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: BarChart(barDataForMonth(monthFilter)))),
                            ]),
                          ),
                        const SizedBox(height: 12),

                        // LINE CHART (Last 7 Days)
                        glass(
                          height: 260,
                          child: Column(children: [
                            const Row(children: [Text('Last 7 Days Expense Trend', style: TextStyle(fontWeight: FontWeight.bold)), const Spacer()]),
                            const SizedBox(height: 8),
                            Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: LineChart(lineDataForLast7Days()))),
                          ]),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),

                if (wide) const SizedBox(width: 14),

                // Right List (Expense History) - Where Update/Delete functionality resides
                Expanded(
                  flex: wide ? 1 : 1,
                  child: Column(children: [
                    Expanded(
                      child: glass(
                        child: indices.isEmpty
                            ? const Center(child: Text('No expenses found.', style: TextStyle(color: Colors.grey)))
                            : ListView.builder(
                          itemCount: indices.length,
                          itemBuilder: (context, idx) {
                            final i = indices[idx];
                            final m = Map.from(box.getAt(i));
                            return Column(
                              children: [
                                // *** DELETE & UPDATE IMPLEMENTATION USING DISMISSIBLE ***
                                Dismissible(
                                  key: Key(i.toString()),
                                  // Background for Delete (Swipe left-to-right)
                                  background: Container(
                                    color: Colors.redAccent,
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.only(left: 16),
                                    child: const Row(children: [Icon(Icons.delete, color: Colors.white), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.white))]),
                                  ),
                                  // Secondary Background for Edit/Update (Swipe right-to-left)
                                  secondaryBackground: Container(
                                    color: Colors.green,
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 16),
                                    child: const Row(mainAxisAlignment: MainAxisAlignment.end, children: [Icon(Icons.edit, color: Colors.white), SizedBox(width: 8), Text('Edit', style: TextStyle(color: Colors.white))]),
                                  ),
                                  confirmDismiss: (dir) async {
                                    if (dir == DismissDirection.startToEnd) {
                                      // **DELETE**: Calls _deleteAt function
                                      return await _deleteAt(i);
                                    } else {
                                      // **UPDATE**: Opens the dialog to edit the expense
                                      openDialog(index: i);
                                      return false; // Don't dismiss, dialog handles update
                                    }
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(color: widget.isDark ? Colors.grey.withOpacity(0.05) : Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                                    child: ListTile(
                                      leading: CircleAvatar(backgroundColor: chartColors[categories.indexOf(m['category'] ?? categories.first) % chartColors.length], child: Text((m['title'] ?? 'E').toString().substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.white))),
                                      title: Text(m['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                                      subtitle: Text('${m['category']} · ${m['date']} · ${m['time']}'),
                                      trailing: Text('₹ ${(m['amount'] ?? 0).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                      onTap: () => openDialog(index: i), // Tap also opens for edit
                                    ),
                                  ),
                                ),
                                const Divider(height: 8, thickness: 1),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ]),
                )
              ]);
            }),
          )
        ]),
      ),
    );
  }

  // Delete function with confirmation dialog
  Future<bool?> _deleteAt(int index) async {
    final m = Map.from(box.getAt(index));
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(title: const Text('Confirm Deletion'), content: Text('Are you sure you want to delete expense: "${m['title']}" (₹${(m['amount'] ?? 0).toStringAsFixed(2)})?'), actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete', style: TextStyle(color: Colors.white))),
      ]),
    );
    if (ok == true) {
      box.deleteAt(index);
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expense Deleted Successfully')));
    }
    return ok;
  }
}