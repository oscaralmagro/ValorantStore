import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
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

void main() => runApp(const App());

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
          navigationBarTheme: NavigationBarThemeData(backgroundColor: panel, indicatorColor: red.withOpacity(.25)),
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
  final String name, icon, kind, price, old;
  final int disc;
  Item(this.name, this.icon, this.kind, this.price, this.old, this.disc);
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
}

final cache = <String, dynamic>{};

Future<Item> resolve(dynamic type, dynamic id, {String price = '', String old = '', int disc = 0}) async {
  final t = types[type];
  if (t == null) return Item('Objeto', '', 'Otro', price, old, disc);
  final key = '${t[0]}/$id';
  try {
    final d = cache[key] ??= await api(key);
    final name = t[1] == 'Título' ? d['titleText'] : d['displayName'];
    return Item('${name ?? 'Objeto'}', '${d['displayIcon'] ?? d['largeArt'] ?? d['fullRender'] ?? ''}', t[1], price, old, disc);
  } catch (_) {
    return Item('Objeto', '', t[1], price, old, disc);
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

  Widget wallet(Map<String, dynamic> w) => Wrap(spacing: 8, children: [
        for (final e in cur.entries)
          if (w[e.key] != null)
            Chip(backgroundColor: panel, side: BorderSide.none, label: Text('${w[e.key]} ${e.value}', style: const TextStyle(fontWeight: FontWeight.w700))),
      ]);

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
          wallet(d.wallet),
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
          title: Text(tab == 0 ? 'Valorant Store' : 'Armas', style: const TextStyle(fontWeight: FontWeight.w800)),
          actions: [if (loggedIn && tab == 0) IconButton(onPressed: logout, icon: const Icon(Icons.logout), tooltip: 'Cerrar sesión')],
        ),
        body: SafeArea(child: IndexedStack(index: tab, children: [storeTab(), const WeaponsTab()])),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Tienda'),
            NavigationDestination(icon: Icon(Icons.gps_fixed), label: 'Armas'),
          ],
        ),
      );
}

class ItemTile extends StatelessWidget {
  final Item i;
  const ItemTile(this.i, {super.key});
  @override
  Widget build(BuildContext c) => Container(
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
      );
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
  late Future<dynamic> f = api('weapons');

  @override
  Widget build(BuildContext c) => FutureBuilder(
        future: f,
        builder: (c, s) {
          if (s.hasError) {
            return Center(child: TextButton(onPressed: () => setState(() => f = api('weapons')), child: const Text('Error al cargar. Reintentar')));
          }
          if (!s.hasData) return const Center(child: CircularProgressIndicator(color: red));
          final list = s.data as List;
          return ListView(padding: const EdgeInsets.all(16), children: [
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

String skinImg(Map s) {
  if (s['displayIcon'] != null) return '${s['displayIcon']}';
  for (final l in (s['levels'] ?? [])) { if (l['displayIcon'] != null) return '${l['displayIcon']}'; }
  for (final x in (s['chromas'] ?? [])) { if (x['fullRender'] != null) return '${x['fullRender']}'; }
  return '';
}

class WeaponPage extends StatelessWidget {
  final Map w;
  const WeaponPage(this.w, {super.key});
  @override
  Widget build(BuildContext c) {
    final skins = [for (final s in (w['skins'] as List)) if (skinImg(s).isNotEmpty) s];
    return Scaffold(
      appBar: AppBar(backgroundColor: bg, title: Text('${w['displayName']}', style: const TextStyle(fontWeight: FontWeight.w800))),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.05),
        itemCount: skins.length,
        itemBuilder: (_, i) {
          final s = skins[i];
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
      ),
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

  Widget title(String t) => Padding(padding: const EdgeInsets.only(top: 22, bottom: 10), child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)));

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(backgroundColor: bg, title: Text('${widget.s['displayName']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
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
