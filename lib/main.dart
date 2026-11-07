import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
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
    await notif.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    await notif.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
  } catch (_) {}
  await loadFavs();
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
  final puuid = jsonDecode((await http.post(Uri.parse('https://auth.riotgames.com/userinfo'), headers: h)).body)['sub'];
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
    try {
      final w = await http.get(Uri.parse('https://pd.$s.a.pvp.net/store/v1/wallet/$puuid'), headers: sh);
      out.wallet = Map<String, dynamic>.from(jsonDecode(w.body)['Balances'] ?? {});
    } catch (_) {}
    try {
      final x = await http.get(Uri.parse('https://pd.$s.a.pvp.net/account-xp/v1/players/$puuid'), headers: sh);
      out.level = (jsonDecode(x.body)['Progress']?['Level'] ?? 0) as int;
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
                Image.memory(curIcon(e.key), height: 26, width: 26, fit: BoxFit.contain, filterQuality: FilterQuality.high),
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
            Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('Colección completa: ${b.price}', style: const TextStyle(color: red, fontWeight: FontWeight.w800, fontSize: 16))),
            grid(b.items),
          ],
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
          title: Text(['Valorant Store', 'Armas', 'Pase de temporada', 'Agentes', 'Esports'][tab], style: const TextStyle(fontWeight: FontWeight.w800)),
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
          ]),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() { tab = i; visited.add(i); }),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Tienda'),
            NavigationDestination(icon: Icon(Icons.gps_fixed), label: 'Armas'),
            NavigationDestination(icon: Icon(Icons.military_tech_outlined), selectedIcon: Icon(Icons.military_tech), label: 'Pase'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Agentes'),
            NavigationDestination(icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events), label: 'Esports'),
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
            Text(i.price, style: const TextStyle(color: red, fontWeight: FontWeight.w800, fontSize: 16)),
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

Map tag(dynamic s, dynamic w) => Map<String, dynamic>.from(s)..['_w'] = w['displayIcon'];

String skinImg(Map s) {
  for (final x in (s['chromas'] ?? [])) { if (x['fullRender'] != null) return '${x['fullRender']}'; }
  for (final l in (s['levels'] ?? [])) { if (l['displayIcon'] != null) return '${l['displayIcon']}'; }
  if (s['displayIcon'] != null) return '${s['displayIcon']}';
  return '${s['_w'] ?? ''}';
}

class SkinGrid extends StatelessWidget {
  final List skins;
  final bool scroll;
  const SkinGrid(this.skins, {this.scroll = true, super.key});
  @override
  Widget build(BuildContext c) => GridView.builder(
        shrinkWrap: !scroll,
        physics: scroll ? null : const NeverScrollableScrollPhysics(),
        padding: scroll ? const EdgeInsets.all(16) : EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.05),
        itemCount: skins.length,
        itemBuilder: (_, i) {
          final s = skins[i] as Map;
          return GestureDetector(
            onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => SkinPage(s))),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(6)),
              child: Column(children: [
                Expanded(child: Image.network(skinImg(s), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox())),
                const SizedBox(height: 6),
                Text('${s['displayName']}', maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, color: sand, fontSize: 13)),
              ]),
            ),
          );
        },
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
  final String name, img, video, thumb;
  Variant(this.name, this.img, this.video, this.thumb);
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
    styles = [
      for (final x in (s['chromas'] ?? []))
        Variant('${x['displayName'] ?? ''}', '${x['fullRender'] ?? x['displayIcon'] ?? skinImg(s)}', '${x['streamedVideo'] ?? ''}', '${x['swatch'] ?? x['fullRender'] ?? ''}'),
    ];
    final ls = (s['levels'] ?? []) as List;
    levels = [
      for (int i = 0; i < ls.length; i++)
        if (ls[i]['streamedVideo'] != null) Variant('Nivel ${i + 1}', '${ls[i]['displayIcon'] ?? skinImg(s)}', '${ls[i]['streamedVideo']}', ''),
    ];
    sel = styles.isNotEmpty ? styles.first : (levels.isNotEmpty ? levels.first : Variant('${s['displayName']}', skinImg(s), '', ''));
  }

  Widget row(List<Variant> l) => SizedBox(
        height: 118,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final v in l)
            GestureDetector(
              onTap: () => setState(() => sel = v),
              child: Container(
                width: 92,
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(6), border: Border.all(color: identical(v, sel) ? red : Colors.transparent, width: 2)),
                child: Column(children: [
                  Expanded(child: v.thumb.isEmpty ? const Icon(Icons.play_circle_outline, size: 32, color: Colors.white54) : Image.network(v.thumb, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox())),
                  const SizedBox(height: 4),
                  Text(v.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.white70)),
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
          const SizedBox(height: 14),
          if (sel.video.isNotEmpty)
            VideoBox(sel.video)
          else
            const Padding(padding: EdgeInsets.all(12), child: Text('No hay vídeo disponible para esta variante.', style: TextStyle(color: Colors.white54))),
          if (styles.isNotEmpty) ...[title('Estilos'), row(styles)],
          if (levels.isNotEmpty) ...[title('Animaciones por nivel'), row(levels)],
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
const notifDetails = NotificationDetails(android: AndroidNotificationDetails('store', 'Tienda', importance: Importance.high, priority: Priority.high));
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
          if (i.price.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(i.price, style: const TextStyle(color: red, fontWeight: FontWeight.w800, fontSize: 20))),
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


// ---------- Iconos de moneda (incrustados) ----------
const _vpB64 = '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';
const _rpB64 = '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';
const _kcB64 = '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';
final _curBytes = <String, Uint8List>{};
Uint8List curIcon(String id) => _curBytes[id] ??= base64Decode(cur[id] == 'VP' ? _vpB64 : cur[id] == 'RP' ? _rpB64 : _kcB64);

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
                            child: Stack(children: [
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
        Text('${a['description'] ?? ''}', style: const TextStyle(color: Colors.white70, height: 1.4)),
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
                    Text('${ab['description']}', style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.35)),
                  ]),
                ),
              ]),
            ),
      ]),
    );
  }
}

// ---------- Esports (Classic de cada equipo) ----------
class EsportsTab extends StatefulWidget {
  const EsportsTab({super.key});
  @override
  State<EsportsTab> createState() => _EsportsTabState();
}

class _EsportsTabState extends State<EsportsTab> {
  late Future<List> f = catalog();
  String q = '';

  @override
  Widget build(BuildContext c) => FutureBuilder<List>(
        future: f,
        builder: (c, s) {
          if (s.hasError) return Center(child: TextButton(onPressed: () => setState(() { resetCatalog(); f = catalog(); }), child: const Text('Error al cargar. Reintentar')));
          if (!s.hasData) return const Center(child: CircularProgressIndicator(color: red));
          Map? classic;
          for (final w in s.data!) { if ('${w['uuid']}' == '29a0cfab-485b-f5d5-779a-b59f85e204a8') classic = w as Map; }
          final all = <dynamic>[];
          if (classic != null) {
            for (final k in classic['skins']) {
              if (okSkin(k) && RegExp(r'vct|champions|esports', caseSensitive: false).hasMatch('${k['displayName']}')) all.add(tag(k, classic));
            }
            all.sort((a, b) => '${a['displayName']}'.compareTo('${b['displayName']}'));
          }
          final found = [for (final k in all) if ('${k['displayName']}'.toLowerCase().contains(q)) k];
          return ListView(padding: const EdgeInsets.all(16), children: [
            const Text('Classic de los equipos', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('${all.length} skins Classic de equipos y torneos. Pulsa una para ver sus estilos y vídeos.', style: const TextStyle(color: Colors.white60, height: 1.4)),
            const SizedBox(height: 12),
            searchField('Buscar equipo (ej. SEN, Fnatic, Liquid...)', (v) => setState(() => q = v.trim().toLowerCase())),
            const SizedBox(height: 12),
            if (all.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Text('No se han encontrado Classic de esports.', style: TextStyle(color: Colors.white54)))
            else
              SkinGrid(found, scroll: false),
          ]);
        },
      );
}
