import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

const red = Color(0xFFFF4655), bg = Color(0xFF0F1923), panel = Color(0xFF1B2733), sand = Color(0xFFECE8E1);
const vault = FlutterSecureStorage();
const authUrl = 'https://auth.riotgames.com/authorize?client_id=play-valorant-web-prod&redirect_uri=https%3A%2F%2Fplayvalorant.com%2Fopt_in&response_type=token%20id_token&scope=account%20openid&nonce=1';
const vpId = '85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741';

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
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: panel,
            indicatorColor: red.withOpacity(.25),
          ),
        ),
        home: const Home(),
      );
}

class Skin {
  final String name, icon;
  final int price;
  Skin(this.name, this.icon, this.price);
}

Future<(List<Skin>, int)> fetchStore(String token) async {
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
    final layout = jsonDecode(r.body)['SkinsPanelLayout'];
    final prices = <String, int>{};
    for (final o in (layout['SingleItemStoreOffers'] ?? [])) {
      prices[o['OfferID']] = (o['Cost']?[vpId] ?? 0) as int;
    }
    final ids = List<String>.from(layout['SingleItemOffers']);
    final skins = await Future.wait(ids.map((id) async {
      final d = jsonDecode(utf8.decode((await http.get(Uri.parse('https://valorant-api.com/v1/weapons/skinlevels/$id?language=es-ES'))).bodyBytes))['data'];
      return Skin(d['displayName'], d['displayIcon'] ?? '', prices[id] ?? 0);
    }));
    return (skins, (layout['SingleItemOffersRemainingDurationInSeconds'] ?? 0) as int);
  }
  throw 'No se pudo cargar la tienda. Vuelve a iniciar sesión.';
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0, secs = 0;
  bool loading = true, loggedIn = false;
  String? error;
  List<Skin> skins = [];
  Timer? timer;

  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (secs > 0 && --secs == 0) load();
      if (mounted && tab == 0 && skins.isNotEmpty) setState(() {});
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
      final (s, t) = await fetchStore(token);
      setState(() { skins = s; secs = t; loggedIn = true; loading = false; });
    } catch (e) {
      setState(() { error = '$e'; loggedIn = true; loading = false; });
    }
  }

  Future<void> login() async {
    final t = await Navigator.push<Map<String, String>>(context, MaterialPageRoute(builder: (_) => const LoginPage()));
    if (t == null) return;
    final secsValid = int.tryParse(t['expires_in'] ?? '3600') ?? 3600;
    await vault.write(key: 'token', value: t['access_token']);
    await vault.write(key: 'exp', value: '${DateTime.now().millisecondsSinceEpoch + (secsValid - 60) * 1000}');
    load();
  }

  Future<void> logout() async {
    await vault.deleteAll();
    setState(() { loggedIn = false; skins = []; });
  }

  String get clock {
    final h = secs ~/ 3600, m = secs % 3600 ~/ 60, s = secs % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget storeTab() {
    if (loading) return const Center(child: CircularProgressIndicator(color: red));
    if (!loggedIn) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.shopping_bag_outlined, size: 64, color: red),
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
          ]),
        ),
      );
    }
    return RefreshIndicator(
      color: red,
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        const Text('Tienda de hoy', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Se renueva en $clock', style: const TextStyle(color: Colors.white60, fontSize: 15)),
        const SizedBox(height: 16),
        if (error != null) Padding(padding: const EdgeInsets.all(12), child: Text(error!, style: const TextStyle(color: red))),
        for (final s in skins) SkinCard(s),
        const SizedBox(height: 12),
        const SupportBox(),
      ]),
    );
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(
          backgroundColor: bg,
          title: Text(tab == 0 ? 'Valorant Store' : 'Apoyar', style: const TextStyle(fontWeight: FontWeight.w800)),
          actions: [if (loggedIn && tab == 0) IconButton(onPressed: logout, icon: const Icon(Icons.logout), tooltip: 'Cerrar sesión')],
        ),
        body: SafeArea(
          child: IndexedStack(index: tab, children: [
            storeTab(),
            ListView(padding: const EdgeInsets.all(16), children: const [SupportBox()]),
          ]),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Tienda'),
            NavigationDestination(icon: Icon(Icons.favorite_border), selectedIcon: Icon(Icons.favorite), label: 'Apoyar'),
          ],
        ),
      );
}

class SkinCard extends StatelessWidget {
  final Skin s;
  const SkinCard(this.s, {super.key});
  @override
  Widget build(BuildContext c) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(6),
          border: const Border(left: BorderSide(color: red, width: 4)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 110,
            width: double.infinity,
            child: s.icon.isEmpty ? const SizedBox() : Image.network(s.icon, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text(s.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: sand))),
            Text('${s.price} VP', style: const TextStyle(color: red, fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
        ]),
      );
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
