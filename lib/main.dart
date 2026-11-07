import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:webview_flutter/webview_flutter.dart';

const red = Color(0xFFFF4655), bg = Color(0xFF0F1923), panel = Color(0xFF1B2733), sand = Color(0xFFECE8E1);
const vault = FlutterSecureStorage();
const authUrl = 'https://auth.riotgames.com/authorize?client_id=play-valorant-web-prod&redirect_uri=https%3A%2F%2Fplayvalorant.com%2Fopt_in&response_type=token%20id_token&scope=account%20openid&nonce=1';
const cur = {
  '85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741': 'VP',
  'e59aa87c-4cbf-517a-5983-6e81511be9b7': 'RP',
  '85ca954a-41f2-ce94-9b45-8ca3dd39a00d': 'KC',
};
const types = {
  'e7c63390-eda7-46e0-bb7a-a6abdacd2433': ['weapons/skinlevels', 'Skin'],
  '3ad1b2b2-acdb-4524-852f-954a76ddae0a': ['weapons/skinchromas', 'Skin'],
  'dd3bf334-87f3-40bd-b043-682a57a8dc3a': ['buddies/levels', 'Colgante'],
  'd5f120f8-ff8c-4aac-92ea-f2b5acbe9475': ['sprays', 'Spray'],
  '3f296c07-64c3-494c-923b-fe692a4fa1bd': ['playercards', 'Tarjeta'],
  'de7caa6b-adf7-4588-bbd1-143831e786c6': ['playertitles', 'Título'],
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  try {
    await notif.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'), iOS: DarwinInitializationSettings()));
    await notif.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    await notif.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: true, sound: true);
  } catch (_) {}
  await loadFavs();
  await loadOfferCache();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        title: 'Tienda Valorant',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: bg,
          colorScheme: const ColorScheme.dark(primary: red, surface: bg),
          navigationBarTheme: NavigationBarThemeData(backgroundColor: panel, indicatorColor: red.withOpacity(.25), labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
        ),
        home: const Home(),
      );
}

String money(dynamic m) {
  if (m is! Map || m.isEmpty) return '';
  final e = m.entries.first;
  return '${e.value} ${cur[e.key] ?? ''}';
}

String clock(int s) {
  final h = s ~/ 3600, m = s % 3600 ~/ 60, x = s % 60;
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(h)}:${p(m)}:${p(x)}';
}

Future<dynamic> api(String path) async {
  final r = await http.get(Uri.parse('https://valorant-api.com/v1/$path${path.contains('?') ? '&' : '?'}language=es-ES'));
  return jsonDecode(utf8.decode(r.bodyBytes))['data'];
}

class Item {
  final String id, name, icon, kind, price, old;
  final int disc;
  Item(this.id, this.name, this.icon, this.kind, this.price, this.old, this.disc);
}

class Bundle {
  final String name, icon, price;
  int secs;
  final List<Item> items;
  Bundle(this.name, this.icon, this.price, this.secs, this.items);
}

class StoreData {
  List<Item> daily = [], night = [], acc = [];
  List<Bundle> bundles = [];
  int dailySecs = 0, nightSecs = 0, accSecs = 0;
  Map<String, dynamic> wallet = {};
  int level = 0;
  List contracts = [];
  Set<String> agents = {};
  bool agentsOk = false;
  List esports = [];
  Map<String, String>? hdr;
  String? shard, puuid, name;
}

final cache = <String, dynamic>{};

Future<Item> resolve(dynamic type, dynamic id, {String price = '', String old = '', int disc = 0}) async {
  final t = types[type];
  if (t == null) return Item('$id', 'Objeto', '', 'Otro', price, old, disc);
  final key = '${t[0]}/$id';
  try {
    final d = cache[key] ??= await api(key);
    final name = t[1] == 'Título' ? d['titleText'] : d['displayName'];
    return Item('$id', '${name ?? 'Objeto'}', '${d['displayIcon'] ?? d['largeArt'] ?? d['fullRender'] ?? ''}', t[1], price, old, disc);
  } catch (_) {
    return Item('$id', 'Objeto', '', t[1], price, old, disc);
  }
}

Future<StoreData> fetchStore(String token) async {
  final h = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  final ent = jsonDecode((await http.post(Uri.parse('https://entitlements.auth.riotgames.com/api/token/v1'), headers: h, body: '{}')).body)['entitlements_token'];
  final ui = jsonDecode((await http.post(Uri.parse('https://auth.riotgames.com/userinfo'), headers: h)).body);
  final puuid = ui['sub'];
  final ver = jsonDecode((await http.get(Uri.parse('https://valorant-api.com/v1/version'))).body)['data']['riotClientVersion'];
  final plat = base64Encode(utf8.encode(jsonEncode({'platformType': 'PC', 'platformOS': 'Windows', 'platformOSVersion': '10.0.19042.1.256.64bit', 'platformChipset': 'Unknown'})));
  final Map<String, String> sh = {...h, 'X-Riot-Entitlements-JWT': '$ent', 'X-Riot-ClientVersion': '$ver', 'X-Riot-ClientPlatform': plat};
  final saved = await vault.read(key: 'shard');
  for (final s in {if (saved != null) saved, 'eu', 'na', 'ap', 'kr'}) {
    final r = await http.post(Uri.parse('https://pd.$s.a.pvp.net/store/v3/storefront/$puuid'), headers: sh, body: '{}');
    if (r.statusCode != 200) continue;
    await vault.write(key: 'shard', value: s);
    final j = jsonDecode(r.body) as Map;
    final out = StoreData();
    out.hdr = sh;
    out.shard = s;
    out.puuid = '$puuid';
    out.name = '${ui['acct']?['game_name'] ?? ''}#${ui['acct']?['tag_line'] ?? ''}';
    try {
      final w = await http.get(Uri.parse('https://pd.$s.a.pvp.net/store/v1/wallet/$puuid'), headers: sh);
      out.wallet = Map<String, dynamic>.from(jsonDecode(w.body)['Balances'] ?? {});
    } catch (_) {}
    try {
      final x = await http.get(Uri.parse('https://pd.$s.a.pvp.net/account-xp/v1/players/$puuid'), headers: sh);
      out.level = ((jsonDecode(x.body)['Progress']?['Level'] ?? 0) as num).toInt();
    } catch (_) {}
    try {
      final x = await http.get(Uri.parse('https://pd.$s.a.pvp.net/contracts/v1/contracts/$puuid'), headers: sh);
      out.contracts = (jsonDecode(x.body)['Contracts'] ?? []) as List;
    } catch (_) {}
    try {
      final x = await http.get(Uri.parse('https://pd.$s.a.pvp.net/store/v1/entitlements/$puuid/01bb38e1-da47-4e6a-9b3d-945fe4655707'), headers: sh);
      final ents = (jsonDecode(x.body)['Entitlements'] ?? []) as List;
      out.agents = {for (final e in ents) '${e['ItemID']}'.toLowerCase()};
      out.agentsOk = true;
    } catch (_) {}
    try {
      final x = await http.get(Uri.parse('https://pd.$s.a.pvp.net/store/v1/offers/'), headers: sh);
      final offs = (jsonDecode(x.body)['Offers'] ?? []) as List;
      final m = <String, Map>{}, keep = <String, Map>{};
      for (final o in offs) {
        final cost = o['Cost'];
        if (cost is! Map || cost.isEmpty) continue;
        for (final r in (o['Rewards'] ?? [])) {
          final id = '${r['ItemID']}'.toLowerCase();
          m[id] = cost;
          final ty = '${r['ItemTypeID']}';
          if (ty == 'e7c63390-eda7-46e0-bb7a-a6abdacd2433' || ty == '3ad1b2b2-acdb-4524-852f-954a76ddae0a') keep[id] = cost;
        }
        m['${o['OfferID']}'.toLowerCase()] = cost;
      }
      if (m.isNotEmpty) {
        offerCost..clear()..addAll(m);
        offersLoaded = true;
        offerTick.value++;
        saveOfferCache(keep);
      }
    } catch (_) {}
    final lay = j['SkinsPanelLayout'];
    final prices = <String, String>{};
    for (final o in (lay['SingleItemStoreOffers'] ?? [])) {
      prices['${o['OfferID']}'] = money(o['Cost']);
    }
    out.dailySecs = (lay['SingleItemOffersRemainingDurationInSeconds'] ?? 0) as int;
    out.daily = await Future.wait([
      for (final id in lay['SingleItemOffers']) resolve('e7c63390-eda7-46e0-bb7a-a6abdacd2433', id, price: prices['$id'] ?? ''),
    ]);
    for (final b in (j['FeaturedBundle']?['Bundles'] ?? [])) {
      dynamic meta;
      try { meta = await api('bundles/${b['DataAssetID']}'); } catch (_) {}
      final items = await Future.wait([
        for (final i in (b['Items'] ?? []))
          resolve(i['Item']['ItemTypeID'], i['Item']['ItemID'],
              price: '${i['DiscountedPrice']} ${cur[i['CurrencyID']] ?? ''}',
              old: ((i['DiscountPercent'] ?? 0) as num) > 0 ? '${i['BasePrice']}' : '',
              disc: ((i['DiscountPercent'] ?? 0) as num).round()),
      ]);
      out.bundles.add(Bundle('${meta?['displayName'] ?? 'Colección'}', '${meta?['displayIcon'] ?? ''}',
          money(b['TotalDiscountedCost'] ?? b['TotalBaseCost']), (b['DurationRemainingInSeconds'] ?? 0) as int, items));
    }
    final bs = j['BonusStore'];
    if (bs != null) {
      out.nightSecs = (bs['BonusStoreRemainingDurationInSeconds'] ?? 0) as int;
      out.night = await Future.wait([
        for (final o in (bs['BonusStoreOffers'] ?? []))
          resolve(o['Offer']['Rewards'][0]['ItemTypeID'], o['Offer']['Rewards'][0]['ItemID'],
              price: money(o['DiscountCosts']), old: money(o['Offer']['Cost']), disc: ((o['DiscountPercent'] ?? 0) as num).round()),
      ]);
    }
    final ac = j['AccessoryStore'];
    if (ac != null) {
      out.accSecs = (ac['AccessoryStoreRemainingDurationInSeconds'] ?? 0) as int;
      out.acc = await Future.wait([
        for (final o in (ac['AccessoryStoreOffers'] ?? []))
          resolve(o['Offer']['Rewards'][0]['ItemTypeID'], o['Offer']['Rewards'][0]['ItemID'], price: money(o['Offer']['Cost'])),
      ]);
    }
    return out;
  }
  throw 'No se pudo cargar la tienda. Vuelve a iniciar sesión.';
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  final visited = <int>{0};
  bool loading = true, loggedIn = false;
  String? error;
  StoreData? data;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final d = data;
      if (d == null) return;
      if (d.dailySecs > 0 && --d.dailySecs == 0) { load(); return; }
      if (d.nightSecs > 0) d.nightSecs--;
      if (d.accSecs > 0) d.accSecs--;
      for (final b in d.bundles) { if (b.secs > 0) b.secs--; }
      if (mounted && tab == 0) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    final token = await vault.read(key: 'token');
    final exp = int.tryParse(await vault.read(key: 'exp') ?? '') ?? 0;
    if (token == null || DateTime.now().millisecondsSinceEpoch > exp) {
      setState(() { loggedIn = false; loading = false; });
      return;
    }
    try {
      final d = await fetchStore(token);
      setState(() { data = d; loggedIn = true; loading = false; });
      afterStore(d);
      buildEsports(d).then((_) { if (mounted) setState(() {}); });
    } catch (e) {
      setState(() { error = '$e'; loggedIn = true; loading = false; });
    }
  }

  Future<void> login() async {
    final t = await Navigator.push<Map<String, String>>(context, MaterialPageRoute(builder: (_) => const LoginPage()));
    if (t == null) return;
    final valid = int.tryParse(t['expires_in'] ?? '3600') ?? 3600;
    await vault.write(key: 'token', value: t['access_token']);
    await vault.write(key: 'exp', value: '${DateTime.now().millisecondsSinceEpoch + (valid - 60) * 1000}');
    load();
  }

  Future<void> logout() async {
    await vault.deleteAll();
    setState(() { loggedIn = false; data = null; });
  }

  Widget section(String title, int secs) => Padding(
        padding: const EdgeInsets.only(top: 26, bottom: 12),
        child: Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
          if (secs > 0) Text(clock(secs), style: const TextStyle(color: Colors.white60)),
        ]),
      );

  Widget grid(List<Item> l) => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: .85,
        children: [for (final i in l) ItemTile(i)],
      );

  Widget wallet(StoreData d) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(6)),
        child: Wrap(spacing: 22, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final e in cur.entries)
            if (d.wallet[e.key] != null)
              Row(mainAxisSize: MainAxisSize.min, children: [
                CurIcon(e.key, size: 26, tint: sand),
                const SizedBox(width: 8),
                Text(fmt(d.wallet[e.key]), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              ]),
          if (d.level > 0) Text('Nivel ${d.level}', style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget storeTab() {
    if (loading) return const Center(child: CircularProgressIndicator(color: red));
    if (!loggedIn) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Image.asset('assets/icon.png', height: 120),
            const SizedBox(height: 20),
            const Text('Tu tienda de Valorant', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            const Text('Inicia sesión en la página oficial de Riot. La app nunca ve tu contraseña.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, height: 1.4)),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: login,
              style: FilledButton.styleFrom(backgroundColor: red, minimumSize: const Size.fromHeight(54), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4)))),
              child: const Text('Iniciar sesión con Riot', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            const SizedBox(height: 36),
            const SupportBox(),
          ]),
        ),
      );
    }
    final d = data;
    return RefreshIndicator(
      color: red,
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        if (error != null) Padding(padding: const EdgeInsets.all(12), child: Text(error!, style: const TextStyle(color: red))),
        if (d != null) ...[
          if (favHits(d).isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              color: red.withOpacity(.2),
              child: Text('♥ En tu tienda hoy: ${favHits(d).map((i) => i.name).join(', ')}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          wallet(d),
          section('Tienda diaria', d.dailySecs),
          for (final i in d.daily) Padding(padding: const EdgeInsets.only(bottom: 12), child: SizedBox(height: 190, child: ItemTile(i))),
          for (final b in d.bundles) ...[
            section(b.name, b.secs),
            if (b.icon.isNotEmpty) ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(b.icon, errorBuilder: (_, __, ___) => const SizedBox())),
            Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Row(children: [const Text('Colección completa: ', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 16)), Price(b.price)])),
            grid(b.items),
          ],
          if (d.esports.isNotEmpty) ...[section('Esports', 0), SkinGrid(d.esports, scroll: false, badge: 'ESPORTS')],
          if (d.night.isNotEmpty) ...[section('Mercado nocturno', d.nightSecs), grid(d.night)],
          if (d.acc.isNotEmpty) ...[section('Accesorios', d.accSecs), grid(d.acc)],
        ],
        const SizedBox(height: 32),
        const SupportBox(),
      ]),
    );
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(
          backgroundColor: bg,
          title: Text(['Valorant Store', 'Armas', 'Pase de temporada', 'Agentes', 'Esports', 'Perfil'][tab], style: const TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const FavPage())), icon: const Icon(Icons.favorite_border), tooltip: 'Mi armario'),
            if (loggedIn && tab == 0) IconButton(onPressed: logout, icon: const Icon(Icons.logout), tooltip: 'Cerrar sesión'),
          ],
        ),
        body: SafeArea(
          child: IndexedStack(index: tab, children: [
            storeTab(),
            visited.contains(1) ? const WeaponsTab() : const SizedBox(),
            visited.contains(2) ? PassTab(data) : const SizedBox(),
            visited.contains(3) ? AgentsTab(data) : const SizedBox(),
            visited.contains(4) ? const EsportsTab() : const SizedBox(),
            visited.contains(5) ? ProfileTab(data) : const SizedBox(),
          ]),
        ),
        bottomNavigationBar: NavigationBar(
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() { tab = i; visited.add(i); }),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Tienda'),
            NavigationDestination(icon: Icon(Icons.gps_fixed), label: 'Armas'),
            NavigationDestination(icon: Icon(Icons.military_tech_outlined), selectedIcon: Icon(Icons.military_tech), label: 'Pase'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Agentes'),
            NavigationDestination(icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events), label: 'Esports'),
            NavigationDestination(icon: Icon(Icons.account_circle_outlined), selectedIcon: Icon(Icons.account_circle), label: 'Perfil'),
          ],
        ),
      );
}

class ItemTile extends StatelessWidget {
  final Item i;
  const ItemTile(this.i, {super.key});
  @override
  Widget build(BuildContext c) => GestureDetector(
      onTap: () => openItem(c, i),
      child: Stack(children: [
        Container(
        decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(6), border: const Border(left: BorderSide(color: red, width: 4))),
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Center(
              child: i.icon.isEmpty
                  ? const Icon(Icons.badge_outlined, size: 40, color: Colors.white38)
                  : Image.network(i.icon, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported)),
            ),
          ),
          const SizedBox(height: 8),
          Text(i.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: sand)),
          Text(i.kind, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (i.disc > 0)
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), color: red, child: Text('-${i.disc}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
            if (i.old.isNotEmpty) Text(i.old, style: const TextStyle(color: Colors.white38, decoration: TextDecoration.lineThrough)),
            if (i.price.isNotEmpty) Price(i.price),
          ]),
        ]),
        ),
        Positioned(top: 0, right: 0, child: FavButton(i.id, i.name, i.icon, i.kind)),
      ]));
}

const catNames = {
  'Melee': 'Cuerpo a cuerpo', 'Sidearm': 'Pistolas', 'SMG': 'Subfusiles',
  'Shotgun': 'Escopetas', 'Rifle': 'Rifles', 'Sniper': 'Francotiradores', 'Heavy': 'Pesadas',
};

class WeaponsTab extends StatefulWidget {
  const WeaponsTab({super.key});
  @override
  State<WeaponsTab> createState() => _WeaponsTabState();
}

class _WeaponsTabState extends State<WeaponsTab> {
  late Future<List> f = catalog();
  String q = '';

  @override
  Widget build(BuildContext c) => FutureBuilder<List>(
        future: f,
        builder: (c, s) {
          if (s.hasError) {
            return Center(child: TextButton(onPressed: () => setState(() { resetCatalog(); f = catalog(); }), child: const Text('Error al cargar. Reintentar')));
          }
          if (!s.hasData) return const Center(child: CircularProgressIndicator(color: red));
          final list = s.data!;
          final found = q.isEmpty
              ? <dynamic>[]
              : [for (final w in list) for (final k in w['skins']) if (okSkin(k) && '${k['displayName']}'.toLowerCase().contains(q)) tag(k, w)];
          return ListView(padding: const EdgeInsets.all(16), children: [
            searchField('Buscar skin (ej. Reaver, Prime...)', (v) => setState(() => q = v.trim().toLowerCase())),
            if (q.isNotEmpty) ...[
              Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('${found.length} resultados', style: const TextStyle(color: Colors.white60))),
              SkinGrid(found, scroll: false),
            ] else
              for (final e in catNames.entries) ...[
                Padding(padding: const EdgeInsets.only(top: 12, bottom: 10), child: Text(e.value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.35,
                  children: [
                    for (final w in list)
                      if ('${w['category']}'.endsWith(e.key))
                        GestureDetector(
                          onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => WeaponPage(w))),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(6)),
                            child: Column(children: [
                              Expanded(child: Image.network('${w['displayIcon']}', fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox())),
                              const SizedBox(height: 6),
                              Text('${w['displayName']}', style: const TextStyle(fontWeight: FontWeight.w700, color: sand)),
                            ]),
                          ),
                        ),
                  ],
                ),
              ],
          ]);
        },
      );
}

Widget searchField(String hint, ValueChanged<String> on) => TextField(
      onChanged: on,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: panel,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      ),
    );

bool okSkin(dynamic s) {
  final n = '${s['displayName']}'.toLowerCase();
  return !n.contains('aleatorio') && !n.contains('random');
}

Map tag(dynamic s, dynamic w) => Map<String, dynamic>.from(s)..['_w'] = w['displayIcon']..['_cat'] = w['category'];

String skinImg(Map s) {
  for (final x in (s['chromas'] ?? [])) { if (x['fullRender'] != null) return '${x['fullRender']}'; }
  for (final l in (s['levels'] ?? [])) { if (l['displayIcon'] != null) return '${l['displayIcon']}'; }
  if (s['displayIcon'] != null) return '${s['displayIcon']}';
  return '${s['_w'] ?? ''}';
}

class SkinGrid extends StatelessWidget {
  final List skins;
  final bool scroll;
  final String badge;
  const SkinGrid(this.skins, {this.scroll = true, this.badge = '', super.key});
  @override
  Widget build(BuildContext c) => ValueListenableBuilder<int>(
        valueListenable: offerTick,
        builder: (_, __, ___) => GridView.builder(
          shrinkWrap: !scroll,
          physics: scroll ? null : const NeverScrollableScrollPhysics(),
          padding: scroll ? const EdgeInsets.all(16) : EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .92),
          itemCount: skins.length,
          itemBuilder: (_, i) {
            final s = skins[i] as Map;
            final p = skinPrice(s);
            return GestureDetector(
              onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => SkinPage(s))),
              child: Stack(fit: StackFit.expand, children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(6)),
                  child: Column(children: [
                    Expanded(child: Image.network(skinImg(s), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox())),
                    const SizedBox(height: 6),
                    Text('${s['displayName']}', maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, color: sand, fontSize: 13)),
                    const SizedBox(height: 4),
                    SizedBox(height: 20, child: p != null ? Price(p, size: 14) : null),
                  ]),
                ),
                if (badge.isNotEmpty)
                  Positioned(top: 0, left: 0, child: Container(color: red, padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), child: Text(badge, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11)))),
              ]),
            );
          },
        ),
      );
}

class WeaponPage extends StatefulWidget {
  final Map w;
  const WeaponPage(this.w, {super.key});
  @override
  State<WeaponPage> createState() => _WeaponPageState();
}

class _WeaponPageState extends State<WeaponPage> {
  String q = '';
  @override
  Widget build(BuildContext c) {
    final w = widget.w;
    final skins = [for (final s in (w['skins'] as List)) if (okSkin(s) && '${s['displayName']}'.toLowerCase().contains(q)) tag(s, w)];
    return Scaffold(
      appBar: AppBar(backgroundColor: bg, title: Text('${w['displayName']}', style: const TextStyle(fontWeight: FontWeight.w800))),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: searchField('Buscar skin de ${w['displayName']}', (v) => setState(() => q = v.trim().toLowerCase()))),
        Expanded(child: SkinGrid(skins)),
      ]),
    );
  }
}

class Variant {
  final String name, img, video, thumb, price;
  Variant(this.name, this.img, this.video, this.thumb, [this.price = '']);
}

class SkinPage extends StatefulWidget {
  final Map s;
  const SkinPage(this.s, {super.key});
  @override
  State<SkinPage> createState() => _SkinPageState();
}

class _SkinPageState extends State<SkinPage> {
  late final List<Variant> styles, levels;
  late Variant sel;

  @override
  void initState() {
    super.initState();
    final s = widget.s;
    final cs = (s['chromas'] ?? []) as List;
    styles = [
      for (int i = 0; i < cs.length; i++)
        Variant('${cs[i]['displayName'] ?? ''}', '${cs[i]['fullRender'] ?? cs[i]['displayIcon'] ?? skinImg(s)}', '${cs[i]['streamedVideo'] ?? ''}', '${cs[i]['swatch'] ?? cs[i]['fullRender'] ?? ''}', i == 0 ? '' : (priceOf('${cs[i]['uuid']}') ?? '≈15 RP')),
    ];
    final ls = (s['levels'] ?? []) as List;
    levels = [
      for (int i = 0; i < ls.length; i++)
        if (ls[i]['streamedVideo'] != null) Variant('Nivel ${i + 1}', '${ls[i]['displayIcon'] ?? skinImg(s)}', '${ls[i]['streamedVideo']}', '', i == 0 ? '' : (priceOf('${ls[i]['uuid']}') ?? '≈10 RP')),
    ];
    sel = styles.isNotEmpty ? styles.first : (levels.isNotEmpty ? levels.first : Variant('${s['displayName']}', skinImg(s), '', ''));
  }

  Widget row(List<Variant> l) => SizedBox(
        height: 138,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final v in l)
            GestureDetector(
              onTap: () => setState(() => sel = v),
              child: Container(
                width: 96,
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(6), border: Border.all(color: identical(v, sel) ? red : Colors.transparent, width: 2)),
                child: Column(children: [
                  Expanded(child: v.thumb.isEmpty ? const Icon(Icons.play_circle_outline, size: 32, color: Colors.white54) : Image.network(v.thumb, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox())),
                  const SizedBox(height: 4),
                  Text(v.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  SizedBox(height: 18, child: v.price.isNotEmpty ? Price(v.price, size: 12) : null),
                ]),
              ),
            ),
        ]),
      );

  String get favId {
    final l = widget.s['levels'] as List?;
    return l != null && l.isNotEmpty ? '${l[0]['uuid']}' : '${widget.s['uuid']}';
  }

  Widget title(String t) => Padding(padding: const EdgeInsets.only(top: 22, bottom: 10), child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)));

  Widget priceLine() {
    final p = skinPrice(widget.s);
    if (p == null) return const SizedBox();
    return Row(children: [const Text('Precio: ', style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w700)), Price(p, size: 20)]);
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(
          backgroundColor: bg,
          title: Text('${widget.s['displayName']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          actions: [FavButton(favId, '${widget.s['displayName']}', skinImg(widget.s), 'Skin')],
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
            height: 200,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(6)),
            child: Image.network(sel.img, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox()),
          ),
          const SizedBox(height: 12),
          priceLine(),
          const SizedBox(height: 14),
          if (sel.video.isNotEmpty)
            VideoBox(sel.video)
          else
            const Padding(padding: EdgeInsets.all(12), child: Text('No hay vídeo disponible para esta variante.', style: TextStyle(color: Colors.white54))),
          if (styles.isNotEmpty) ...[title('Estilos'), row(styles)],
          if (levels.isNotEmpty) ...[title('Animaciones por nivel'), row(levels)],
          if (styles.any((v) => v.price.isNotEmpty) || levels.any((v) => v.price.isNotEmpty))
            const Padding(padding: EdgeInsets.only(top: 12), child: Text('Los estilos y las mejoras de nivel se pagan con Radianita. El símbolo ≈ indica el valor estándar de su gama; el precio exacto se guarda tras iniciar sesión en la tienda.', style: TextStyle(color: Colors.white38, fontSize: 12))),
        ]),
      );
}

class VideoBox extends StatefulWidget {
  final String url;
  const VideoBox(this.url, {super.key});
  @override
  State<VideoBox> createState() => _VideoBoxState();
}

class _VideoBoxState extends State<VideoBox> {
  VideoPlayerController? ctl;

  @override
  void initState() {
    super.initState();
    start();
  }

  void start() {
    ctl?.dispose();
    final n = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    ctl = n;
    n.setLooping(true);
    n.initialize().then((_) {
      if (mounted) { setState(() {}); n.play(); }
    });
  }

  @override
  void didUpdateWidget(VideoBox old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) { setState(() {}); start(); }
  }

  @override
  void dispose() {
    ctl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final v = ctl;
    if (v == null || !v.value.isInitialized) {
      return const AspectRatio(aspectRatio: 16 / 9, child: Center(child: CircularProgressIndicator(color: red)));
    }
    return GestureDetector(
      onTap: () => setState(() => v.value.isPlaying ? v.pause() : v.play()),
      child: ClipRRect(borderRadius: BorderRadius.circular(6), child: AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v))),
    );
  }
}

class SupportBox extends StatelessWidget {
  const SupportBox({super.key});
  Widget btn(String text, String url, Color bgc, Color fg) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SizedBox(
          width: double.infinity,
          height: 64,
          child: FilledButton(
            onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            style: FilledButton.styleFrom(backgroundColor: bgc, foregroundColor: fg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
            child: Text(text, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ),
        ),
      );

  @override
  Widget build(BuildContext c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Apoya al creador', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Si la app te resulta útil, puedes apoyar el proyecto.', style: TextStyle(color: Colors.white60)),
        const SizedBox(height: 16),
        btn('Donate with PayPal 💛', 'https://paypal.me/Oscarlmgr', const Color(0xFFFFC439), const Color(0xFF003087)),
        btn('YouTube ▶', 'https://www.youtube.com/@crosswt7', const Color(0xFFFF0000), Colors.white),
        btn('Twitch 🟣', 'https://www.twitch.tv/oscaralmagroo', const Color(0xFF6441A5), Colors.white),
        const SizedBox(height: 8),
        const Text('App no oficial. No afiliada ni respaldada por Riot Games.', style: TextStyle(color: Colors.white38, fontSize: 12)),
      ]);
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool done = false;
  late final WebViewController ctl = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: (r) => check(r.url) ? NavigationDecision.prevent : NavigationDecision.navigate,
      onPageStarted: check,
    ))
    ..loadRequest(Uri.parse(authUrl));

  bool check(String url) {
    if (!url.startsWith('https://playvalorant.com/opt_in') || !url.contains('access_token=')) return false;
    if (!done) {
      done = true;
      Navigator.pop(context, Uri.splitQueryString(Uri.parse(url).fragment));
    }
    return true;
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('Riot Games')),
        body: SafeArea(child: WebViewWidget(controller: ctl)),
      );
}


// ---------- Armario, catálogo y notificaciones ----------
final notif = FlutterLocalNotificationsPlugin();
const notifDetails = NotificationDetails(android: AndroidNotificationDetails('store', 'Tienda', importance: Importance.high, priority: Priority.high), iOS: DarwinNotificationDetails());
final favs = <String, Map<String, dynamic>>{};
final favTick = ValueNotifier<int>(0);

Future<void> loadFavs() async {
  try {
    for (final f in jsonDecode(await vault.read(key: 'favs') ?? '[]')) {
      favs['${f['id']}'] = Map<String, dynamic>.from(f);
    }
  } catch (_) {}
}

Future<void> toggleFav(String id, String name, String icon, String kind) async {
  if (favs.containsKey(id)) {
    favs.remove(id);
  } else {
    favs[id] = {'id': id, 'name': name, 'icon': icon, 'kind': kind};
  }
  favTick.value++;
  await vault.write(key: 'favs', value: jsonEncode(favs.values.toList()));
}

Future<List>? _cat;
void resetCatalog() => _cat = null;
Future<List> catalog() => _cat ??= api('weapons').then((d) => d as List);

Future<Map?> findSkin(String id) async {
  for (final w in await catalog()) {
    for (final s in w['skins']) {
      for (final l in (s['levels'] ?? [])) { if (l['uuid'] == id) return tag(s, w); }
      for (final x in (s['chromas'] ?? [])) { if (x['uuid'] == id) return tag(s, w); }
    }
  }
  return null;
}

Future<void> openItem(BuildContext c, Item i) async {
  if (i.kind == 'Skin') {
    try {
      final s = await findSkin(i.id);
      if (s != null && c.mounted) {
        Navigator.push(c, MaterialPageRoute(builder: (_) => SkinPage(s)));
        return;
      }
    } catch (_) {}
  }
  if (c.mounted) Navigator.push(c, MaterialPageRoute(builder: (_) => ItemPage(i)));
}

List<Item> favHits(StoreData d) => [
      for (final i in [...d.daily, ...d.night, ...d.acc, for (final b in d.bundles) ...b.items])
        if (favs.containsKey(i.id)) i,
    ];

Future<void> afterStore(StoreData d) async {
  try {
    final reset = tz.TZDateTime.from(DateTime.now().toUtc().add(Duration(seconds: d.dailySecs)), tz.UTC);
    await notif.cancel(1);
    await notif.zonedSchedule(1, 'Tu tienda de Valorant se ha renovado', 'Entra para ver las skins de hoy.', reset, notifDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle, matchDateTimeComponents: DateTimeComponents.time);
    final hits = favHits(d).map((i) => i.name).toList();
    final key = '${DateTime.now().toUtc().toIso8601String().substring(0, 10)}:${hits.join('|')}';
    if (hits.isNotEmpty && await vault.read(key: 'lastHit') != key) {
      await vault.write(key: 'lastHit', value: key);
      await notif.show(2, '¡Tienes una favorita en la tienda!', hits.join(', '), notifDetails);
    }
  } catch (_) {}
}

class FavButton extends StatelessWidget {
  final String id, name, icon, kind;
  const FavButton(this.id, this.name, this.icon, this.kind, {super.key});
  @override
  Widget build(BuildContext c) => ValueListenableBuilder<int>(
        valueListenable: favTick,
        builder: (_, __, ___) => IconButton(
          onPressed: () => toggleFav(id, name, icon, kind),
          tooltip: 'Guardar en mi armario',
          icon: Icon(favs.containsKey(id) ? Icons.favorite : Icons.favorite_border, color: red),
        ),
      );
}

class ItemPage extends StatelessWidget {
  final Item i;
  const ItemPage(this.i, {super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(backgroundColor: bg, title: Text(i.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)), actions: [FavButton(i.id, i.name, i.icon, i.kind)]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
            height: 260,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(6)),
            child: i.icon.isEmpty ? const Icon(Icons.badge_outlined, size: 64, color: Colors.white38) : Image.network(i.icon, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox()),
          ),
          const SizedBox(height: 16),
          Text(i.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          Text(i.kind, style: const TextStyle(color: Colors.white54)),
          if (i.price.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Price(i.price, size: 20)),
        ]),
      );
}

class FavPage extends StatelessWidget {
  const FavPage({super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(backgroundColor: bg, title: const Text('Mi armario', style: TextStyle(fontWeight: FontWeight.w800))),
        body: ValueListenableBuilder<int>(
          valueListenable: favTick,
          builder: (_, __, ___) {
            final l = favs.values.toList();
            if (l.isEmpty) {
              return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Aún no has guardado nada. Pulsa el corazón en cualquier skin, spray, tarjeta o colgante. Si sale en tu tienda, te avisamos.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, height: 1.4))));
            }
            return GridView.count(
              crossAxisCount: 2,
              padding: const EdgeInsets.all(16),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: .85,
              children: [for (final f in l) ItemTile(Item('${f['id']}', '${f['name']}', '${f['icon']}', '${f['kind']}', '', '', 0))],
            );
          },
        ),
      );
}

Future<Map<String, String>>? _ci;
Future<Map<String, String>> curIcons() => _ci ??= api('currencies').then<Map<String, String>>((d) => {for (final x in d) '${x['uuid']}': '${x['displayIcon']}'});
String fmt(dynamic n) => '$n'.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');


// ---------- Iconos de moneda y precios ----------
final offerCost = <String, Map>{};
bool offersLoaded = false;
final offerTick = ValueNotifier<int>(0);

String? priceOf(String? id) {
  if (id == null) return null;
  final c = offerCost[id.toLowerCase()];
  if (c == null || c.isEmpty) return null;
  final e = c.entries.first;
  return '${e.value} ${cur[e.key] ?? ''}';
}

const vpUuid = '85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741';
const tierVp = {
  '12683d76-48d7-84a3-4e09-6985794f0445': 875,
  '0cebb8be-46d7-c12a-d306-e9907bfc5a25': 1275,
  '60bca009-4182-7998-dee7-b8a2558dc369': 1775,
  'e046854e-406c-37f4-6607-19a9ba8426fc': 2175,
  '411e4a55-4e59-7757-41f0-86a53f101bb5': 2475,
};
final teamRe = RegExp(r'vct|champions|esports', caseSensitive: false);
File get offerFile => File('${Directory.systemTemp.path}/vstore_offers.json');

Future<void> loadOfferCache() async {
  try {
    final f = offerFile;
    if (!await f.exists()) return;
    final m = jsonDecode(await f.readAsString()) as Map;
    for (final e in m.entries) {
      final v = e.value as List;
      offerCost['${e.key}'] = {'${v[0]}': v[1]};
    }
    offersLoaded = offerCost.isNotEmpty;
  } catch (_) {}
}

Future<void> saveOfferCache(Map<String, Map> m) async {
  try {
    final out = <String, List>{};
    for (final e in m.entries) {
      if (e.value.isEmpty) continue;
      final c = e.value.entries.first;
      out[e.key] = [c.key, c.value];
    }
    await offerFile.writeAsString(jsonEncode(out));
  } catch (_) {}
}

bool isTeamSkin(Map s) => teamRe.hasMatch('${s['displayName']}');
bool isMeleeSkin(Map s) => '${s['_cat'] ?? ''}'.endsWith('Melee');

String? skinPrice(Map s) {
  final lv = (s['levels'] ?? []) as List;
  final exact = lv.isNotEmpty ? priceOf('${lv[0]['uuid']}') : null;
  if (exact != null) return exact;
  final t = tierVp['${s['contentTierUuid']}'];
  if (t == null || isTeamSkin(s) || isMeleeSkin(s)) return null;
  return '≈$t VP';
}

class CurIcon extends StatelessWidget {
  final String uuid;
  final double size;
  final Color? tint;
  const CurIcon(this.uuid, {this.size = 20, this.tint, super.key});
  @override
  Widget build(BuildContext c) => Image.network(
        'https://media.valorant-api.com/currencies/$uuid/displayicon.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        color: tint,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => Text(cur[uuid] ?? '', style: TextStyle(color: tint ?? Colors.white70, fontSize: size * .6, fontWeight: FontWeight.w800)),
      );
}

class Price extends StatelessWidget {
  final String s;
  final double size;
  final Color color;
  const Price(this.s, {this.size = 16, this.color = red, super.key});
  @override
  Widget build(BuildContext c) {
    final parts = s.trim().split(' ');
    final code = parts.length > 1 ? parts.last : '';
    String? id;
    for (final e in cur.entries) { if (e.value == code) id = e.key; }
    if (id == null) return Text(s, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: size));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(fmt(parts.first), style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: size)),
      const SizedBox(width: 4),
      CurIcon(id, size: size + 4, tint: color),
    ]);
  }
}

Future<void> buildEsports(StoreData d) async {
  if (!offersLoaded) return;
  try {
    final list = await catalog();
    Map? classic;
    for (final w in list) { if ('${w['uuid']}' == '29a0cfab-485b-f5d5-779a-b59f85e204a8') classic = w as Map; }
    if (classic == null) return;
    final out = [];
    for (final k in classic['skins']) {
      if (!okSkin(k)) continue;
      if (!RegExp(r'vct|champions|esports', caseSensitive: false).hasMatch('${k['displayName']}')) continue;
      final lv = (k['levels'] ?? []) as List;
      if (lv.isNotEmpty && priceOf('${lv[0]['uuid']}') != null) out.add(tag(k, classic));
    }
    d.esports = out;
  } catch (_) {}
}

// ---------- Pase de temporada ----------
const rewardEp = {
  'EquippableSkinLevel': ['weapons/skinlevels', 'Skin'],
  'EquippableCharmLevel': ['buddies/levels', 'Colgante'],
  'Spray': ['sprays', 'Spray'],
  'PlayerCard': ['playercards', 'Tarjeta'],
  'Title': ['playertitles', 'Título'],
  'Currency': ['currencies', 'Moneda'],
  'Character': ['agents', 'Agente'],
};

Future<Item> rewardItem(Map r) async {
  final t = rewardEp['${r['type']}'];
  final id = '${r['uuid']}';
  if (t == null) return Item(id, 'Recompensa', '', 'Otro', '', '', 0);
  try {
    final key = '${t[0]}/$id';
    final d = cache[key] ??= await api(key);
    var name = '${(t[1] == 'Título' ? d['titleText'] : d['displayName']) ?? 'Recompensa'}';
    if (t[1] == 'Moneda' && r['amount'] != null) name = '${fmt(r['amount'])} $name';
    return Item(id, name, '${d['displayIcon'] ?? d['largeArt'] ?? d['fullRender'] ?? ''}', t[1], '', '', 0);
  } catch (_) {
    return Item(id, 'Recompensa', '', t[1], '', '', 0);
  }
}

Future<Map?>? _passDef;
Future<Map?> passDef() => _passDef ??= () async {
      final seasons = (await api('seasons')) as List;
      final contracts = (await api('contracts')) as List;
      final now = DateTime.now().toUtc();
      Map? act;
      Duration? best;
      for (final s in seasons) {
        final a = DateTime.tryParse('${s['startTime']}'), b = DateTime.tryParse('${s['endTime']}');
        if (a == null || b == null || a.isAfter(now) || !b.isAfter(now)) continue;
        final len = b.difference(a);
        if (best == null || len < best) { best = len; act = s as Map; }
      }
      if (act == null) return null;
      Map? pass;
      for (final c in contracts) {
        final ct = c['content'];
        if (ct != null && ct['relationType'] == 'Season' && ct['relationUuid'] == act['uuid']) { pass = c as Map; break; }
      }
      if (pass == null) return null;
      return {'season': act, 'contract': pass};
    }();

class PassTab extends StatefulWidget {
  final StoreData? data;
  const PassTab(this.data, {super.key});
  @override
  State<PassTab> createState() => _PassTabState();
}

class _PassTabState extends State<PassTab> {
  late Future<Map?> f = passDef();

  @override
  Widget build(BuildContext c) => FutureBuilder<Map?>(
        future: f,
        builder: (c, s) {
          if (s.hasError) return Center(child: TextButton(onPressed: () => setState(() { _passDef = null; f = passDef(); }), child: const Text('Error al cargar. Reintentar')));
          if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator(color: red));
          final def = s.data;
          if (def == null) return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No se ha encontrado el pase de temporada actual.', style: TextStyle(color: Colors.white60))));
          final contract = def['contract'] as Map, season = def['season'] as Map;
          final chapters = (contract['content']['chapters'] ?? []) as List;
          final total = [for (final ch in chapters) ...(ch['levels'] ?? [])].length;
          Map? mine;
          for (final x in (widget.data?.contracts ?? [])) { if ('${x['ContractDefinitionID']}'.toLowerCase() == '${contract['uuid']}'.toLowerCase()) mine = x as Map; }
          final reached = (mine?['ProgressionLevelReached'] ?? 0) as int;
          final toward = (mine?['ProgressionTowardsNextLevel'] ?? 0) as int;
          final allLevels = [for (final ch in chapters) ...(ch['levels'] ?? [])];
          final nextXp = reached < allLevels.length ? (allLevels[reached]['xp'] ?? 0) as int : 0;
          final end = DateTime.tryParse('${season['endTime']}');
          final days = end == null ? 0 : end.difference(DateTime.now().toUtc()).inDays;
          final logged = widget.data != null;
          int n = 0;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(6), border: const Border(left: BorderSide(color: red, width: 4))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${contract['displayName'] ?? 'Pase de batalla'}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                if (days >= 0) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Termina en $days días', style: const TextStyle(color: Colors.white60))),
                const SizedBox(height: 14),
                if (logged) ...[
                  Row(children: [
                    Text('Nivel $reached / $total', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: red)),
                    const Spacer(),
                    if (widget.data!.level > 0) Text('Cuenta nivel ${widget.data!.level}', style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: total == 0 ? 0 : reached / total, minHeight: 8, color: red, backgroundColor: Colors.white12),
                  if (nextXp > 0) Padding(padding: const EdgeInsets.only(top: 10), child: Text('Siguiente nivel: ${fmt(toward)} / ${fmt(nextXp)} XP', style: const TextStyle(color: Colors.white70))),
                  if (nextXp > 0) Padding(padding: const EdgeInsets.only(top: 6), child: LinearProgressIndicator(value: (toward / nextXp).clamp(0, 1).toDouble(), minHeight: 5, color: sand, backgroundColor: Colors.white12)),
                ] else
                  const Text('Inicia sesión en la pestaña Tienda para ver tu progreso en el pase.', style: TextStyle(color: Colors.white60, height: 1.4)),
              ]),
            ),
            for (int ci = 0; ci < chapters.length; ci++) ...[
              Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 10),
                child: Text(chapters[ci]['isEpilogue'] == true ? 'Epílogo' : 'Capítulo ${ci + 1}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              if ((chapters[ci]['freeRewards'] ?? []).isNotEmpty) ...[
                const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Recompensas gratis', style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w700))),
                for (final r in chapters[ci]['freeRewards']) RewardRow(r as Map, tag: 'Gratis'),
                const SizedBox(height: 10),
              ],
              for (final lv in (chapters[ci]['levels'] ?? [])) RewardRow((lv['reward'] ?? {}) as Map, level: ++n, done: logged && n <= reached, xp: (lv['xp'] ?? 0) as int),
            ],
            const SizedBox(height: 14),
            const Text('Las recompensas premium solo se obtienen si tienes el pase premium de la temporada.', style: TextStyle(color: Colors.white38, fontSize: 12)),
          ]);
        },
      );
}

class RewardRow extends StatelessWidget {
  final Map r;
  final int level, xp;
  final bool done;
  final String tag;
  const RewardRow(this.r, {this.level = 0, this.xp = 0, this.done = false, this.tag = '', super.key});
  @override
  Widget build(BuildContext c) => FutureBuilder<Item>(
        future: rewardItem(r),
        builder: (c, s) {
          final it = s.data;
          return GestureDetector(
            onTap: it == null ? null : () => openItem(c, it),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(6), border: Border(left: BorderSide(color: done ? red : Colors.white12, width: 4))),
              child: Row(children: [
                if (level > 0)
                  SizedBox(width: 34, child: done ? const Icon(Icons.check_circle, color: red) : Text('$level', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, fontSize: 16))),
                SizedBox(
                  width: 64,
                  height: 48,
                  child: it == null || it.icon.isEmpty ? const Icon(Icons.card_giftcard, color: Colors.white38) : Image.network(it.icon, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.card_giftcard, color: Colors.white38)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(it?.name ?? '...', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: sand)),
                    Text([if (it != null) it.kind, if (tag.isNotEmpty) tag, if (xp > 0) '${fmt(xp)} XP'].join(' · '), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  ]),
                ),
              ]),
            ),
          );
        },
      );
}

// ---------- Agentes ----------
Future<List>? _agents;
Future<List> agentList() => _agents ??= api('agents?isPlayableCharacter=true').then((d) => d as List);

Color hexColor(dynamic h, Color fallback) {
  try {
    final s = '$h';
    return Color(int.parse('FF${s.substring(0, 6)}', radix: 16));
  } catch (_) {
    return fallback;
  }
}

class AgentsTab extends StatefulWidget {
  final StoreData? data;
  const AgentsTab(this.data, {super.key});
  @override
  State<AgentsTab> createState() => _AgentsTabState();
}

class _AgentsTabState extends State<AgentsTab> {
  late Future<List> f = agentList();
  int filter = 0;

  bool owned(Map a) => a['isBaseContent'] == true || (widget.data?.agents.contains('${a['uuid']}'.toLowerCase()) ?? false);

  @override
  Widget build(BuildContext c) => FutureBuilder<List>(
        future: f,
        builder: (c, s) {
          if (s.hasError) return Center(child: TextButton(onPressed: () => setState(() { _agents = null; f = agentList(); }), child: const Text('Error al cargar. Reintentar')));
          if (!s.hasData) return const Center(child: CircularProgressIndicator(color: red));
          final all = [for (final a in s.data!) a as Map]..sort((a, b) => '${a['displayName']}'.compareTo('${b['displayName']}'));
          final known = widget.data != null && widget.data!.agentsOk;
          final have = known ? all.where(owned).length : 0;
          final shown = [for (final a in all) if (filter == 0 || !known || (filter == 1 ? owned(a) : !owned(a))) a];
          final roles = <String>[];
          for (final a in shown) { final r = '${a['role']?['displayName'] ?? 'Otros'}'; if (!roles.contains(r)) roles.add(r); }
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (known)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('Tienes $have de ${all.length} agentes', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)))
            else
              const Padding(padding: EdgeInsets.only(bottom: 10), child: Text('Inicia sesión en la pestaña Tienda para ver cuáles tienes.', style: TextStyle(color: Colors.white60))),
            if (known)
              Wrap(spacing: 8, children: [
                for (final e in {0: 'Todos', 1: 'Desbloqueados', 2: 'Bloqueados'}.entries)
                  ChoiceChip(label: Text(e.value), selected: filter == e.key, selectedColor: red.withOpacity(.4), onSelected: (_) => setState(() => filter = e.key)),
              ]),
            for (final r in roles) ...[
              Padding(padding: const EdgeInsets.only(top: 18, bottom: 10), child: Text(r, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: .78,
                children: [
                  for (final a in shown)
                    if ('${a['role']?['displayName'] ?? 'Otros'}' == r)
                      GestureDetector(
                        onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => AgentPage(a, known ? owned(a) : null))),
                        child: Opacity(
                          opacity: known && !owned(a) ? .45 : 1,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(6)),
                            child: Stack(fit: StackFit.expand, children: [
                              Column(children: [
                                Expanded(child: Image.network('${a['displayIcon']}', fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox())),
                                const SizedBox(height: 4),
                                Text('${a['displayName']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: sand, fontSize: 13)),
                              ]),
                              if (known) Positioned(top: 0, right: 0, child: Icon(owned(a) ? Icons.check_circle : Icons.lock, size: 18, color: owned(a) ? red : Colors.white70)),
                            ]),
                          ),
                        ),
                      ),
                ],
              ),
            ],
          ]);
        },
      );
}

class AgentPage extends StatelessWidget {
  final Map a;
  final bool? owned;
  const AgentPage(this.a, this.owned, {super.key});
  @override
  Widget build(BuildContext c) {
    final cols = (a['backgroundGradientColors'] ?? []) as List;
    final c1 = cols.isNotEmpty ? hexColor(cols[0], panel) : panel, c2 = cols.length > 1 ? hexColor(cols[1], bg) : bg;
    return Scaffold(
      appBar: AppBar(backgroundColor: bg, title: Text('${a['displayName']}', style: const TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          height: 340,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), gradient: LinearGradient(colors: [c1, c2], begin: Alignment.topLeft, end: Alignment.bottomRight)),
          child: Stack(children: [
            if (a['background'] != null) Positioned.fill(child: Opacity(opacity: .25, child: Image.network('${a['background']}', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()))),
            Positioned.fill(child: Image.network('${a['fullPortrait'] ?? a['displayIcon']}', fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox())),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          if (a['role'] != null) ...[
            if (a['role']['displayIcon'] != null) Image.network('${a['role']['displayIcon']}', width: 24, height: 24, errorBuilder: (_, __, ___) => const SizedBox()),
            const SizedBox(width: 8),
            Text('${a['role']['displayName']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ],
          const Spacer(),
          if (owned != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              color: owned! ? red : Colors.white24,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(owned! ? Icons.check : Icons.lock, size: 16),
                const SizedBox(width: 4),
                Text(owned! ? 'Desbloqueado' : 'Bloqueado', style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
        const SizedBox(height: 10),
        Text(cleanTags(a['description']), style: const TextStyle(color: Colors.white70, height: 1.4)),
        const Padding(padding: EdgeInsets.only(top: 22, bottom: 10), child: Text('Habilidades', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        for (final ab in (a['abilities'] ?? []))
          if (ab['displayName'] != null && '${ab['displayName']}'.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(6)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 44, height: 44, child: ab['displayIcon'] == null ? const SizedBox() : Image.network('${ab['displayIcon']}', errorBuilder: (_, __, ___) => const SizedBox())),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${ab['displayName']}', style: const TextStyle(fontWeight: FontWeight.w800, color: sand)),
                    const SizedBox(height: 4),
                    Text(cleanTags(ab['description']), style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.35)),
                  ]),
                ),
              ]),
            ),
      ]),
    );
  }
}

// ---------- Esports (eventos, partidos y equipos) ----------
const esportsKey = '0TvQnueqKa5mxJntVWt0w4LpLfEkrV1Ta8rQBb9Z';
const monthsEs = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
String dayStr(DateTime d) => '${d.day} ${monthsEs[d.month - 1]}';
String hourStr(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

Future<List> eventList() async {
  try {
    return (await api('events')) as List;
  } catch (_) {
    return [];
  }
}

Future<List> esportsSchedule() async {
  final all = <dynamic>[];
  Future<Map?> page([String? tok]) async {
    try {
      final r = await http.get(Uri.parse('https://esports-api.service.valorantesports.com/persisted/val/getSchedule?hl=en-US${tok != null ? '&pageToken=$tok' : ''}'), headers: {'x-api-key': esportsKey});
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return j['data']?['schedule'] as Map?;
    } catch (_) {
      return null;
    }
  }
  final first = await page();
  if (first == null) return all;
  all.addAll((first['events'] ?? []) as List);
  String? newer = first['pages']?['newer'] as String?;
  for (int i = 0; i < 3 && newer != null; i++) {
    final p = await page(newer);
    if (p == null) break;
    all.addAll((p['events'] ?? []) as List);
    newer = p['pages']?['newer'] as String?;
  }
  String? older = first['pages']?['older'] as String?;
  for (int i = 0; i < 3 && older != null; i++) {
    final p = await page(older);
    if (p == null) break;
    all.addAll((p['events'] ?? []) as List);
    older = p['pages']?['older'] as String?;
  }
  return all;
}

class EsportsTab extends StatefulWidget {
  const EsportsTab({super.key});
  @override
  State<EsportsTab> createState() => _EsportsTabState();
}

class _EsportsTabState extends State<EsportsTab> {
  late Future<List<List>> f = Future.wait([eventList(), esportsSchedule()]);

  Widget head(String t) => Padding(padding: const EdgeInsets.only(top: 26, bottom: 12), child: Text(t, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFFE8B923))));

  Widget teamLogo(Map t, {double size = 28}) => SizedBox(
        width: size,
        height: size,
        child: t['image'] == null ? const SizedBox() : Image.network('${t['image']}', fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox()),
      );

  Widget eventCard(Map e, bool live) {
    final a = DateTime.tryParse('${e['startTime']}')?.toLocal(), b = DateTime.tryParse('${e['endTime']}')?.toLocal();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: const LinearGradient(colors: [Color(0xFF4A3508), Color(0xFF1B1405)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        border: const Border(left: BorderSide(color: Color(0xFFE8B923), width: 4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          color: live ? red : const Color(0xFFE8B923),
          child: Text(live ? 'EN CURSO' : 'PRÓXIMO', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: live ? Colors.white : Colors.black)),
        ),
        const SizedBox(height: 10),
        Text('${e['displayName']}'.toUpperCase(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, height: 1.1)),
        if (a != null && b != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${dayStr(a)} – ${dayStr(b)}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<List<List>>(
        future: f,
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator(color: red));
          final now = DateTime.now().toUtc();
          final live = <Map>[], soon = <Map>[];
          for (final e in s.data![0]) {
            final a = DateTime.tryParse('${e['startTime']}'), b = DateTime.tryParse('${e['endTime']}');
            if (a == null || b == null || b.isBefore(now)) continue;
            (a.isAfter(now) ? soon : live).add(e as Map);
          }
          soon.sort((x, y) => '${x['startTime']}'.compareTo('${y['startTime']}'));
          final sched = [
            for (final e in s.data![1])
              if (e is Map && e['match'] != null && '${e['state']}' != 'completed') e,
          ]..sort((x, y) => '${x['startTime']}'.compareTo('${y['startTime']}'));
          final next = sched.take(10).toList();
          final teams = <String, Map>{};
          for (final e in s.data![1]) {
            if (e is! Map || e['match'] == null) continue;
            for (final t in (e['match']['teams'] ?? [])) {
              if (t is Map && t['code'] != null && '${t['code']}'.toUpperCase() != 'TBD') teams['${t['code']}'] = t;
            }
          }
          final teamList = teams.values.toList()..sort((a, b) => '${a['code']}'.compareTo('${b['code']}'));
          return ListView(padding: const EdgeInsets.all(16), children: [
            const Text('Esports', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            for (final e in live) eventCard(e, true),
            for (final e in soon.take(3)) eventCard(e, false),
            if (live.isEmpty && soon.isEmpty) const Padding(padding: EdgeInsets.only(top: 12), child: Text('No hay eventos en curso ni anunciados ahora mismo.', style: TextStyle(color: Colors.white54))),
            FilledButton(
              onPressed: () => launchUrl(Uri.parse('https://valorantesports.com'), mode: LaunchMode.externalApplication),
              style: FilledButton.styleFrom(backgroundColor: sand, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(48), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(3)))),
              child: const Text('DETALLES DEL EVENTO', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            head('PRÓXIMOS PARTIDOS'),
            if (next.isEmpty)
              const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('NO HAY PARTIDOS PRÓXIMOS, VUELVE MÁS TARDE', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 12))))
            else
              for (final e in next)
                Builder(builder: (_) {
                  final t = (e['match']['teams'] ?? []) as List;
                  final d = DateTime.tryParse('${e['startTime']}')?.toLocal();
                  final liveNow = '${e['state']}' == 'inProgress';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(6), border: Border(left: BorderSide(color: liveNow ? red : const Color(0xFFE8B923), width: 4))),
                    child: Row(children: [
                      for (int i = 0; i < t.length && i < 2; i++) ...[
                        if (i == 1) const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('vs', style: TextStyle(color: Colors.white38))),
                        teamLogo(t[i] as Map),
                        const SizedBox(width: 6),
                        Text('${t[i]['code'] ?? t[i]['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      ],
                      const Spacer(),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(liveNow ? 'EN DIRECTO' : (d == null ? '' : '${dayStr(d)} ${hourStr(d)}'), style: TextStyle(color: liveNow ? red : sand, fontWeight: FontWeight.w700, fontSize: 13)),
                        Text('${e['league']?['name'] ?? ''}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ]),
                    ]),
                  );
                }),
            if (teams.isNotEmpty) ...[
              head('EQUIPOS'),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final t in teamList)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: panel,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [teamLogo(t, size: 26), const SizedBox(width: 8), Text('${t['code']}', style: const TextStyle(fontWeight: FontWeight.w800))]),
                  ),
              ]),
            ],
            head("PICK'EMS"),
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFFE8B923),
              child: const Text('PREDICE A LOS GANADORES · JUEGA CON AMIGOS · GANA RECOMPENSAS', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, height: 1.4)),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text("Los Pick'Ems y sus recompensas (títulos, colgantes) solo se pueden jugar y ver dentro del cliente de VALORANT en PC.", style: TextStyle(color: Colors.white54, height: 1.4, fontSize: 13)),
            ),
            const TeamClassics(),
          ]);
        },
      );
}

class TeamClassics extends StatefulWidget {
  const TeamClassics({super.key});
  @override
  State<TeamClassics> createState() => _TeamClassicsState();
}

class _TeamClassicsState extends State<TeamClassics> {
  late Future<List> f = catalog();
  String q = '';

  @override
  Widget build(BuildContext c) => FutureBuilder<List>(
        future: f,
        builder: (c, s) {
          if (s.hasError) return Center(child: TextButton(onPressed: () => setState(() { resetCatalog(); f = catalog(); }), child: const Text('Error al cargar. Reintentar')));
          if (!s.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: red)));
          Map? classic;
          for (final w in s.data!) { if ('${w['uuid']}' == '29a0cfab-485b-f5d5-779a-b59f85e204a8') classic = w as Map; }
          final all = <dynamic>[];
          if (classic != null) {
            for (final k in classic['skins']) {
              if (okSkin(k) && teamRe.hasMatch('${k['displayName']}')) all.add(tag(k, classic));
            }
            all.sort((a, b) => '${a['displayName']}'.compareTo('${b['displayName']}'));
          }
          final found = [for (final k in all) if ('${k['displayName']}'.toLowerCase().contains(q)) k];
          final yr = 'VCT${DateTime.now().year % 100}';
          final thisYear = [for (final k in found) if ('${k['displayName']}'.toUpperCase().contains(yr)) k];
          final older = [for (final k in found) if (!'${k['displayName']}'.toUpperCase().contains(yr)) k];
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 26, bottom: 6), child: Text('CLASSIC DE EQUIPOS (VCT)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFFE8B923)))),
            Text('${all.length} skins Classic de equipos y torneos. Pulsa una para ver sus estilos y vídeos.', style: const TextStyle(color: Colors.white60, height: 1.4)),
            const SizedBox(height: 12),
            searchField('Buscar equipo (ej. SEN, Fnatic, Liquid...)', (v) => setState(() => q = v.trim().toLowerCase())),
            const SizedBox(height: 12),
            if (found.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Sin resultados.', style: TextStyle(color: Colors.white54))),
            if (thisYear.isNotEmpty) ...[
              Padding(padding: const EdgeInsets.only(top: 18, bottom: 10), child: Text('CLASSIC DE ESTE AÑO ($yr)', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              SkinGrid(thisYear, scroll: false, badge: 'ESPORTS'),
            ],
            if (older.isNotEmpty) ...[
              const Padding(padding: EdgeInsets.only(top: 22, bottom: 10), child: Text('CLASSIC DE AÑOS ANTERIORES', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              SkinGrid(older, scroll: false, badge: 'ESPORTS'),
            ],
          ]);
        },
      );
}

// ---------- Perfil: carrera y colección ----------
const winColor = Color(0xFF2ECC8F);
Future<List>? _tiers;
Future<List> tierList() => _tiers ??= api('competitivetiers').then((d) => d as List);
Future<List>? _mapsF;
Future<List> mapList() => _mapsF ??= api('maps').then((d) => d as List);

const queueEs = {
  'competitive': 'Competitivo', 'unrated': 'Sin clasificar', 'swiftplay': 'Juego rápido', 'spikerush': 'Spike Rush',
  'deathmatch': 'Combate a muerte', 'ggteam': 'Escalada', 'hurm': 'Combate por equipos', 'premier': 'Premier',
  'snowball': 'Snowball Fight', 'onefa': 'Replicación', 'custom': 'Personalizada',
};

String cleanTags(dynamic t) => '${t ?? ''}'.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();

final nameCache = <String, String>{};

Future<void> fillNames(StoreData d, List players) async {
  final need = <String>{};
  for (final x in players) {
    final id = '${x['subject']}';
    if (!nameCache.containsKey(id)) need.add(id);
  }
  if (need.isNotEmpty) {
    try {
      final r = await http.put(Uri.parse('https://pd.${d.shard}.a.pvp.net/name-service/v2/players'),
          headers: {...?d.hdr, 'Content-Type': 'application/json'}, body: jsonEncode(need.toList()));
      if (r.statusCode == 200) {
        for (final e in (jsonDecode(utf8.decode(r.bodyBytes)) as List)) {
          final g = '${e['GameName'] ?? ''}';
          if (g.isNotEmpty) nameCache['${e['Subject']}'] = '$g#${e['TagLine'] ?? ''}';
        }
      }
    } catch (_) {}
  }
  for (final x in players) {
    final n = nameCache['${x['subject']}'];
    if (n != null && '${x['gameName'] ?? ''}'.isEmpty) {
      final i = n.indexOf('#');
      x['gameName'] = i < 0 ? n : n.substring(0, i);
      x['tagLine'] = i < 0 ? '' : n.substring(i + 1);
    }
  }
}

Future<dynamic> pvp(StoreData d, String path) async {
  final r = await http.get(Uri.parse('https://pd.${d.shard}.a.pvp.net/$path'), headers: d.hdr);
  if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
  return jsonDecode(utf8.decode(r.bodyBytes));
}

Future<List>? _seasonsF;
Future<List> seasonList() => _seasonsF ??= api('seasons').then((d) => d as List);

Future<dynamic> exprInfo(String id) async {
  for (final k in ['sprays', 'flex']) {
    try {
      final r = await api('$k/$id');
      if (r is Map) return r;
    } catch (_) {}
  }
  return null;
}

Future<Map> loadProfile(StoreData d) async {
  final out = <String, dynamic>{};
  String? err;
  for (final v in ['v3', 'v2']) {
    try {
      out['loadout'] = await pvp(d, 'personalization/$v/players/${d.puuid}/playerloadout');
      break;
    } catch (e) {
      err = '$v: $e';
    }
  }
  if (out['loadout'] == null) out['loErr'] = err;
  try { out['mmr'] = await pvp(d, 'mmr/v1/players/${d.puuid}'); } catch (_) {}
  try {
    final x = await pvp(d, 'account-xp/v1/players/${d.puuid}');
    final l = x['Progress']?['Level'];
    if (l is num && l > 0) out['level'] = l.toInt();
  } catch (_) {}
  try {
    final id = out['loadout']?['Identity']?['PlayerCardID'];
    if (id != null) out['card'] = await api('playercards/$id');
    final tid = out['loadout']?['Identity']?['PlayerTitleID'];
    if (tid != null) out['title'] = await api('playertitles/$tid');
  } catch (_) {}
  try { out['tiers'] = await tierList(); } catch (_) {}
  try { out['seasons'] = await seasonList(); } catch (_) {}
  return out;
}

Future<List> loadMatches(StoreData d) async {
  final h = await pvp(d, 'match-history/v1/history/${d.puuid}?startIndex=0&endIndex=10');
  final ids = [for (final m in (h['History'] ?? [])) '${m['MatchID']}'];
  List agents = [], maps = [];
  try { agents = await agentList(); } catch (_) {}
  try { maps = await mapList(); } catch (_) {}
  final res = await Future.wait([
    for (final id in ids.take(8))
      () async {
        try {
          final j = await pvp(d, 'match-details/v1/matches/$id');
          await fillNames(d, j['players'] as List);
          final me = (j['players'] as List).firstWhere((p) => '${p['subject']}' == d.puuid) as Map;
          Map? mine, other;
          for (final t in (j['teams'] ?? [])) {
            if ('${t['teamId']}' == '${me['teamId']}') { mine = t as Map; } else { other = t as Map; }
          }
          int result = 2;
          if (mine != null) {
            result = mine['won'] == true ? 1 : ((other != null && mine['roundsWon'] == other['roundsWon']) ? 0 : -1);
          }
          String agent = '', mapName = '';
          for (final a in agents) { if ('${a['uuid']}'.toLowerCase() == '${me['characterId']}'.toLowerCase()) agent = '${a['displayIconSmall'] ?? a['displayIcon']}'; }
          for (final m in maps) { if ('${m['mapUrl']}' == '${j['matchInfo']?['mapId']}') mapName = '${m['displayName']}'; }
          final st = (me['stats'] ?? {}) as Map;
          final q = '${j['matchInfo']?['queueID'] ?? ''}';
          return <String, dynamic>{
            'agent': agent,
            'map': mapName,
            'result': result,
            'kda': '${st['kills'] ?? 0} / ${st['deaths'] ?? 0} / ${st['assists'] ?? 0}',
            'score': '${st['score'] ?? 0}',
            'rounds': (mine != null && other != null) ? '${mine['roundsWon']}-${other['roundsWon']}' : '',
            'queue': queueEs[q] ?? q,
            'raw': j,
            'me': d.puuid,
            'meTeam': '${me['teamId']}',
          };
        } catch (_) {
          return null;
        }
      }(),
  ]);
  return [for (final r in res) if (r != null) r];
}

class ProfileTab extends StatefulWidget {
  final StoreData? data;
  const ProfileTab(this.data, {super.key});
  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  int sub = 0;
  StoreData? _d;
  Future<Map>? pf;
  Future<List>? mf;

  @override
  Widget build(BuildContext c) {
    final d = widget.data;
    if (!identical(_d, d)) {
      _d = d;
      if (d != null && d.hdr != null) {
        pf = loadProfile(d);
        mf = loadMatches(d);
      } else {
        pf = null;
        mf = null;
      }
    }
    if (pf == null || d == null) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Inicia sesión en la pestaña Tienda para ver tu carrera y tu colección.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, height: 1.4))));
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [
          for (final e in {0: 'Carrera', 1: 'Colección'}.entries)
            Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(e.value), selected: sub == e.key, selectedColor: red.withOpacity(.4), onSelected: (_) => setState(() => sub = e.key))),
        ]),
      ),
      Expanded(
        child: FutureBuilder<Map>(
          future: pf,
          builder: (c, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator(color: red));
            return sub == 0 ? CareerView(d, s.data!, mf!) : CollectionView(s.data!);
          },
        ),
      ),
    ]);
  }
}

class CareerView extends StatefulWidget {
  final StoreData d;
  final Map p;
  final Future<List> matches;
  const CareerView(this.d, this.p, this.matches, {super.key});
  @override
  State<CareerView> createState() => _CareerViewState();
}

class _CareerViewState extends State<CareerView> {
  String? sel;

  Widget head(String t) => Padding(padding: const EdgeInsets.only(top: 24, bottom: 10), child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)));

  @override
  Widget build(BuildContext c) {
    final p = widget.p, d = widget.d;
    final card = p['card'], title = p['title'], mmr = p['mmr'];
    final lvl0 = p['level'] ?? p['loadout']?['Identity']?['AccountLevel'];
    final lvl = (lvl0 is num && lvl0 > 0) ? lvl0 : (d.level > 0 ? d.level : null);
    final tiers = (p['tiers'] as List?) ?? [];
    final tierTable = tiers.isNotEmpty ? ((tiers.last['tiers'] ?? []) as List) : [];
    Map? tierOf(int n) {
      for (final x in tierTable) { if (x['tier'] == n) return x as Map; }
      return null;
    }
    final lcu = mmr?['LatestCompetitiveUpdate'];
    final tier = ((lcu?['TierAfterUpdate'] as num?) ?? 0).toInt();
    final rr = ((lcu?['RankedRatingAfterUpdate'] as num?) ?? 0).toInt();
    final t = tierOf(tier);

    final defs = <String, Map>{};
    for (final s in ((p['seasons'] as List?) ?? [])) { defs['${s['uuid']}'.toLowerCase()] = s as Map; }
    String label(String id) {
      final s = defs[id.toLowerCase()];
      if (s == null) return id.substring(0, 8).toUpperCase();
      final par = defs['${s['parentUuid']}'.toLowerCase()];
      return '${par != null ? '${par['displayName']} // ' : ''}${s['displayName']}'.toUpperCase();
    }
    final seasonsInfo = mmr?['QueueSkills']?['competitive']?['SeasonalInfoBySeasonID'];
    final acts = <String>{};
    final nowIso = DateTime.now().toUtc().toIso8601String();
    for (final e in defs.entries) {
      final sd = e.value;
      if (sd['parentUuid'] != null && '${sd['displayName'] ?? ''}'.isNotEmpty && '${sd['startTime'] ?? ''}'.compareTo(nowIso) <= 0) acts.add(e.key);
    }
    if (seasonsInfo is Map) {
      for (final e in seasonsInfo.entries) {
        final v = e.value;
        if (v is Map && (((v['NumberOfGames'] as num?) ?? 0) > 0)) acts.add('${e.key}'.toLowerCase());
      }
    }
    final actList = acts.toList();
    actList.sort((a, b) => '${defs[b.toLowerCase()]?['startTime'] ?? ''}'.compareTo('${defs[a.toLowerCase()]?['startTime'] ?? ''}'));
    final selId = (sel != null && actList.contains(sel)) ? sel : (actList.isNotEmpty ? actList.first : null);
    Map? info;
    if (selId != null && seasonsInfo is Map) {
      for (final e in seasonsInfo.entries) { if ('${e.key}'.toLowerCase() == selId && e.value is Map) info = e.value as Map; }
    }
    final actTier = ((info?['CompetitiveTier'] as num?) ?? 0).toInt();
    final actT = tierOf(actTier);

    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(6), border: const Border(left: BorderSide(color: red, width: 4))),
        child: Row(children: [
          SizedBox(width: 64, height: 64, child: card == null ? const Icon(Icons.person, size: 40) : Image.network('${card['smallArt'] ?? card['displayIcon']}', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 40))),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              if (title != null) Text('${title['titleText'] ?? ''}', style: const TextStyle(color: Colors.white60)),
              if (lvl != null) Text('Nivel de cuenta $lvl', style: const TextStyle(color: sand, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      ),
      head('Competitivo'),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(6)),
        child: Row(children: [
          SizedBox(width: 72, height: 72, child: tier > 0 && t != null ? Image.network('${t['largeIcon']}', errorBuilder: (_, __, ___) => const Icon(Icons.help_outline, size: 48)) : const Icon(Icons.help_outline, size: 48, color: Colors.white54)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tier > 0 && t != null ? '${t['tierName']}' : 'SIN CLASIFICAR', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              if (tier >= 3) Text('$rr RR', style: const TextStyle(color: sand, fontWeight: FontWeight.w700)),
              if (tier == 0) const Text('Juega partidas de colocación para ver tu rango.', style: TextStyle(color: Colors.white54, fontSize: 13)),
            ]),
          ),
        ]),
      ),
      head('Rango por acto'),
      if (actList.isEmpty)
        const Text('No se pudo cargar la lista de actos.', style: TextStyle(color: Colors.white54))
      else ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: panel,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              dropdownColor: panel,
              value: selId,
              items: [for (final a in actList) DropdownMenuItem<String>(value: a, child: Text(label(a), style: const TextStyle(fontWeight: FontWeight.w700)))],
              onChanged: (v) => setState(() => sel = v),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(6)),
          child: Row(children: [
            SizedBox(width: 64, height: 64, child: actTier > 0 && actT != null ? Image.network('${actT['largeIcon']}', errorBuilder: (_, __, ___) => const Icon(Icons.help_outline, size: 44)) : const Icon(Icons.help_outline, size: 44, color: Colors.white54)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(actTier > 0 && actT != null ? '${actT['tierName']}' : (((info?['NumberOfGames'] as num?) ?? 0) == 0 ? 'SIN JUGAR' : 'SIN CLASIFICAR'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                Text(((info?['NumberOfGames'] as num?) ?? 0) == 0 ? 'Sin partidas en este acto' : 'Victorias: ${info?['NumberOfWins'] ?? 0} · Partidas: ${info?['NumberOfGames'] ?? 0}', style: const TextStyle(color: Colors.white60, fontSize: 13)),
              ]),
            ),
          ]),
        ),
      ],
      head('Historial de partidas'),
      FutureBuilder<List>(
        future: widget.matches,
        builder: (c, s) {
          if (s.hasError) return const Text('No se pudo cargar el historial.', style: TextStyle(color: Colors.white54));
          if (!s.hasData) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: red)));
          if (s.data!.isEmpty) return const Text('No hay partidas recientes.', style: TextStyle(color: Colors.white54));
          return Column(children: [
            for (final m in s.data!)
              GestureDetector(
                onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => MatchPage(m as Map, tierTable))),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(6), border: Border(left: BorderSide(color: m['result'] == 1 ? winColor : (m['result'] == -1 ? red : Colors.white38), width: 4))),
                  child: Row(children: [
                    SizedBox(width: 46, height: 46, child: '${m['agent']}'.isEmpty ? const SizedBox() : Image.network('${m['agent']}', errorBuilder: (_, __, ___) => const SizedBox())),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m['result'] == 1 ? 'VICTORIA' : (m['result'] == -1 ? 'DERROTA' : (m['result'] == 0 ? 'EMPATE' : 'PARTIDA')), style: TextStyle(fontWeight: FontWeight.w800, color: m['result'] == 1 ? winColor : (m['result'] == -1 ? red : Colors.white70))),
                        Text('${m['queue']}${'${m['map']}'.isEmpty ? '' : ' · ${m['map']}'}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${m['rounds']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      Text('${m['kda']}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    ]),
                    const Icon(Icons.chevron_right, color: Colors.white38),
                  ]),
                ),
              ),
          ]);
        },
      ),
    ]);
  }
}

class MatchPage extends StatelessWidget {
  final Map m;
  final List tiers;
  const MatchPage(this.m, this.tiers, {super.key});

  Map? tierOf(int n) {
    for (final x in tiers) { if (x['tier'] == n) return x as Map; }
    return null;
  }

  String teamLabel(String id) => id == 'Red' ? 'EQUIPO ROJO' : (id == 'Blue' ? 'EQUIPO AZUL' : id.toUpperCase());

  @override
  Widget build(BuildContext c) {
    final raw = m['raw'] as Map;
    final info = (raw['matchInfo'] ?? {}) as Map;
    final players = [for (final x in (raw['players'] ?? [])) x as Map];
    final teams = {for (final t in (raw['teams'] ?? [])) '${t['teamId']}': t as Map};
    final myTeam = '${m['meTeam']}';
    final ids = <String>[];
    for (final x in players) { if (!ids.contains('${x['teamId']}')) ids.add('${x['teamId']}'); }
    final twoTeams = ids.length == 2;
    if (twoTeams) { ids.sort((a, b) => a == myTeam ? -1 : (b == myTeam ? 1 : 0)); }
    final start = DateTime.fromMillisecondsSinceEpoch((((info['gameStartMillis'] as num?) ?? 0)).toInt()).toLocal();
    final res = m['result'];
    final col = res == 1 ? winColor : (res == -1 ? red : Colors.white70);

    Widget cell(String s, double w, {bool bold = false, Color? color}) => SizedBox(width: w, child: Text(s, textAlign: TextAlign.center, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: 13, color: color ?? sand)));

    Widget block(String title, List<Map> list, Map? team, Map<String, String> icons) {
      list.sort((a, b) => (((b['stats']?['score'] as num?) ?? 0)).compareTo(((a['stats']?['score'] as num?) ?? 0)));
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            if (team != null) Text('${team['roundsWon'] ?? ''}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: team['won'] == true ? winColor : Colors.white70)),
          ]),
        ),
        Row(children: [
          const SizedBox(width: 44),
          const Expanded(child: Text('JUGADOR', style: TextStyle(color: Colors.white38, fontSize: 11))),
          cell('ACS', 44, color: Colors.white38),
          cell('K', 30, color: Colors.white38),
          cell('D', 30, color: Colors.white38),
          cell('A', 30, color: Colors.white38),
        ]),
        const SizedBox(height: 4),
        for (final x in list)
          Builder(builder: (_) {
            final st = (x['stats'] ?? {}) as Map;
            final rounds = (((st['roundsPlayed'] as num?) ?? (team?['roundsPlayed'] as num?) ?? 0)).toInt();
            final score = (((st['score'] as num?) ?? 0)).toInt();
            final acs = rounds > 0 ? score ~/ rounds : score;
            final mine = '${x['subject']}' == '${m['me']}';
            final name = '${x['gameName'] ?? ''}'.isEmpty ? 'Jugador oculto' : '${x['gameName']}#${x['tagLine'] ?? ''}';
            final tr = tierOf((((x['competitiveTier'] as num?) ?? 0)).toInt());
            final icon = icons['${x['characterId']}'.toLowerCase()] ?? '';
            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              color: mine ? red.withOpacity(.25) : panel,
              child: Row(children: [
                SizedBox(width: 36, height: 36, child: icon.isEmpty ? const SizedBox() : Image.network(icon, errorBuilder: (_, __, ___) => const SizedBox())),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(children: [
                    Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: mine ? FontWeight.w800 : FontWeight.w600, fontSize: 13))),
                    if (tr != null && (((x['competitiveTier'] as num?) ?? 0)) > 0) Padding(padding: const EdgeInsets.only(left: 6), child: SizedBox(width: 20, height: 20, child: Image.network('${tr['smallIcon']}', errorBuilder: (_, __, ___) => const SizedBox()))),
                  ]),
                ),
                cell('$acs', 44, bold: true),
                cell('${st['kills'] ?? 0}', 30),
                cell('${st['deaths'] ?? 0}', 30),
                cell('${st['assists'] ?? 0}', 30),
              ]),
            );
          }),
      ]);
    }

    return Scaffold(
      appBar: AppBar(backgroundColor: bg, title: Text('${m['map']}'.isEmpty ? 'Partida' : '${m['map']}', style: const TextStyle(fontWeight: FontWeight.w800))),
      body: FutureBuilder<List>(
        future: agentList().catchError((_) => <dynamic>[]),
        builder: (c, s) {
          final icons = <String, String>{};
          for (final a in (s.data ?? [])) { icons['${a['uuid']}'.toLowerCase()] = '${a['displayIconSmall'] ?? a['displayIcon']}'; }
          return ListView(padding: const EdgeInsets.all(16), children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(6), border: Border(left: BorderSide(color: col, width: 4))),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(res == 1 ? 'VICTORIA' : (res == -1 ? 'DERROTA' : (res == 0 ? 'EMPATE' : 'PARTIDA')), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: col)),
                    Text('${m['queue']} · ${dayStr(start)} ${hourStr(start)}', style: const TextStyle(color: Colors.white60)),
                  ]),
                ),
                Text('${m['rounds']}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
              ]),
            ),
            if (twoTeams)
              for (final id in ids)
                block(id == myTeam ? 'TU EQUIPO · ${teamLabel(id)}' : teamLabel(id), [for (final x in players) if ('${x['teamId']}' == id) x], teams[id], icons)
            else
              block('JUGADORES', [...players], null, icons),
          ]);
        },
      ),
    );
  }
}

class CollectionView extends StatelessWidget {
  final Map p;
  const CollectionView(this.p, {super.key});

  @override
  Widget build(BuildContext c) {
    final lo = p['loadout'];
    if (lo == null) return Center(child: Padding(padding: const EdgeInsets.all(32), child: Text('No se pudo cargar tu colección (${p['loErr'] ?? 'sin respuesta'}).', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54))));
    final guns = <String, Map>{};
    for (final g in (lo['Guns'] ?? [])) { guns['${g['ID']}'.toLowerCase()] = g as Map; }
    final card = p['card'];
    final exprIds = <String>[
      for (final x in (lo['ActiveExpressions'] ?? [])) '${x['AssetID']}',
      for (final x in (lo['Sprays'] ?? [])) '${x['SprayID']}',
    ];
    return FutureBuilder<List>(
      future: catalog(),
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator(color: red));
        Widget head(String t) => Padding(padding: const EdgeInsets.only(top: 22, bottom: 10), child: Text(t, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)));
        return ListView(padding: const EdgeInsets.all(16), children: [
          if (card != null) ...[
            head('Tarjeta de jugador'),
            Center(child: SizedBox(height: 260, child: ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network('${card['largeArt'] ?? card['displayIcon']}', errorBuilder: (_, __, ___) => const SizedBox())))),
          ],
          if (exprIds.isNotEmpty) ...[
            head('Expresiones'),
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final id in exprIds)
                FutureBuilder<dynamic>(
                  future: exprInfo(id),
                  builder: (_, x) => Container(
                    width: 72,
                    height: 72,
                    padding: const EdgeInsets.all(6),
                    color: panel,
                    child: x.hasData && x.data is Map && x.data['displayIcon'] != null ? Image.network('${x.data['displayIcon']}', errorBuilder: (_, __, ___) => const SizedBox()) : const SizedBox(),
                  ),
                ),
            ]),
          ],
          for (final e in catNames.entries) ...[
            head(e.value),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.25,
              children: [
                for (final w in s.data!)
                  if ('${w['category']}'.endsWith(e.key))
                    Builder(builder: (_) {
                      final g = guns['${w['uuid']}'.toLowerCase()];
                      Map? skin;
                      if (g != null) {
                        for (final k in (w['skins'] ?? [])) { if ('${k['uuid']}'.toLowerCase() == '${g['SkinID']}'.toLowerCase()) skin = tag(k, w); }
                      }
                      var img = '${w['displayIcon']}';
                      if (skin != null) {
                        img = skinImg(skin);
                        for (final x in (skin['chromas'] ?? [])) { if ('${x['uuid']}'.toLowerCase() == '${g?['ChromaID']}'.toLowerCase() && x['fullRender'] != null) img = '${x['fullRender']}'; }
                      }
                      return GestureDetector(
                        onTap: skin == null ? null : () => Navigator.push(c, MaterialPageRoute(builder: (_) => SkinPage(skin!))),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(6)),
                          child: Column(children: [
                            Expanded(child: Image.network(img, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox())),
                            const SizedBox(height: 4),
                            Text(skin != null ? '${skin['displayName']}' : '${w['displayName']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: sand, fontSize: 12)),
                          ]),
                        ),
                      );
                    }),
              ],
            ),
          ],
        ]);
      },
    );
  }
}
