import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const coral = Color(0xffff886c);
const cream = Color(0xffffe8d8);
void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const LumaApp()); }

class LumaApp extends StatefulWidget {
  const LumaApp({super.key});
  @override State<LumaApp> createState() => _LumaAppState();
}
class _LumaAppState extends State<LumaApp> {
  bool night = false;
  @override Widget build(BuildContext context) {
    final bg = night ? const Color(0xff090914) : const Color(0xff160b20);
    final surface = night ? const Color(0xff181827) : const Color(0xff28172f);
    return MaterialApp(debugShowCheckedModeBanner:false, title:'LumaLink', theme:ThemeData(useMaterial3:true, brightness:Brightness.dark, scaffoldBackgroundColor:bg, colorScheme:ColorScheme.dark(primary:coral, surface:surface), fontFamily:'Roboto'), home:Home(night:night, toggleNight:()=>setState(()=>night=!night)));
  }
}

class Home extends StatefulWidget {
  final bool night; final VoidCallback toggleNight;
  const Home({super.key,required this.night,required this.toggleNight});
  @override State<Home> createState()=>_HomeState();
}
class _HomeState extends State<Home> with SingleTickerProviderStateMixin {
  final ip=TextEditingController(), port=TextEditingController(text:'8765'), code=TextEditingController();
  final http=HttpClient()..connectionTimeout=const Duration(seconds:8);
  Process? host; StreamSubscription<String>? events; Uint8List? frame; String? cookie; String hostCode=''; String error=''; String hint='';
  bool starting=false, connecting=false, sharing=false, watching=false, paused=false, landscape=false; int run=0, preset=1;
  late AnimationController pulse;
  bool get windows => Platform.isWindows;
  @override void initState(){super.initState();pulse=AnimationController(vsync:this,duration:const Duration(seconds:4))..repeat(reverse:true);if(windows) findIp();}
  Future<void> findIp() async {
    try {
      final interfaces=await NetworkInterface.list(type:InternetAddressType.IPv4);
      for(final n in interfaces){ for(final a in n.addresses){if(isPrivate(a.address)){if(mounted && ip.text.isEmpty){ip.text=a.address;setState((){hint='Detected ${n.name}. Check that this is your Wi-Fi address.';});}return;}}}
      if(mounted)setState(()=>hint='Enter the IPv4 address shown by ipconfig on Windows.');
    } catch (_) { if(mounted)setState(()=>hint='Enter the IPv4 address shown by ipconfig on Windows.'); }
  }
  bool isPrivate(String text){final x=text.split('.');if(x.length!=4)return false;final n=x.map(int.tryParse).toList();if(n.any((e)=>e==null||e<0||e>255))return false;return n[0]==10||(n[0]==172&&n[1]!>=16&&n[1]!<=31)||(n[0]==192&&n[1]==168);}
  bool validate(){final p=int.tryParse(port.text.trim()); if(!isPrivate(ip.text.trim())||p==null||p<1024||p>65535){setState(()=>error='Enter a private IPv4 address and a port from 1024 to 65535.');return false;}return true;}
  String get origin=>'http://${ip.text.trim()}:${port.text.trim()}';
  Future<void> startHost() async {
    if(!validate()||starting||sharing)return;
    setState((){starting=true;error='';});
    if(host!=null){send({'action':'start','ip':ip.text.trim(),'port':int.parse(port.text.trim())});return;}
    try {
      final executable=File(Platform.resolvedExecutable).parent.uri.resolve('lumalink_host.exe').toFilePath();
      final proc=await Process.start(executable,[]);
      if(!mounted){proc.kill();return;} host=proc;
      events=proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line){
        try{final e=jsonDecode(line) as Map<String,dynamic>; if(!mounted)return;
          switch(e['type']){
            case 'started': setState((){starting=false;sharing=true;hostCode=e['code'] as String;}); break;
            case 'stopped': setState((){sharing=false;starting=false;hostCode='';});break;
            case 'error': setState((){starting=false;error='Could not start sharing: ${e['message']}';});break;
            case 'request': approve(e);break;
          }
        }catch (_) { if(mounted)setState(()=>error='The host sent an invalid response.'); }
      },onError:(Object e){if(mounted)setState((){starting=false;sharing=false;error='Host error: $e';});});
      proc.stderr.transform(utf8.decoder).listen((_){});
      proc.exitCode.then((exit){if(mounted && identical(host,proc))setState((){host=null;starting=false;if(sharing){sharing=false;hostCode='';error='The sharing helper stopped.';}});});
      send({'action':'start','ip':ip.text.trim(),'port':int.parse(port.text.trim())});
    }catch(e){if(mounted)setState((){starting=false;error='Could not start the sharing helper. Use the complete Windows build folder. ($e)';});}
  }
  void send(Map<String,dynamic> command){try{host?.stdin.writeln(jsonEncode(command));}catch(_){if(mounted)setState(()=>error='The host is no longer available.');}}
  Future<void> approve(Map<String,dynamic> request) async {
    final allowed=await showDialog<bool>(context:context,barrierDismissible:false,builder:(c)=>AlertDialog(backgroundColor:const Color(0xff2c1935),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(24)),title:const Text('Allow this device?'),content:Text('A phone at ${request['ip']} is asking to view your primary screen. It will see everything on that screen. Only allow a device you recognize.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Deny')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Allow viewing'))]));
    send({'action':'decision','id':request['id'],'allow':allowed==true});
  }
  void stopHost(){send({'action':'stop'});setState((){sharing=false;hostCode='';error='';});}
  Future<void> pair() async {
    if(!validate()||connecting)return;
    if(!RegExp(r'^\d{6}$').hasMatch(code.text.trim())){setState(()=>error='Enter the six-digit code from Windows.');return;}
    setState((){connecting=true;error='Waiting for approval on the PC…';});
    try {
      final request=await http.postUrl(Uri.parse('$origin/api/pair'));request.headers.set('Origin',origin);request.headers.contentType=ContentType.json;request.write(jsonEncode({'code':code.text.trim()}));
      final response=await request.close().timeout(const Duration(seconds:70));final body=await utf8.decoder.bind(response).join();
      if(response.statusCode!=200)throw Exception(body);
      final match=response.cookies.where((c)=>c.name=='ll_session').toList();if(match.isEmpty)throw Exception('No session returned');
      cookie='${match.first.name}=${match.first.value}';if(!mounted)return;
      setState((){connecting=false;watching=true;paused=false;error='';});final id=++run; captureLoop(id);
    } catch(e){if(mounted)setState((){connecting=false;error='Could not connect: ${e.toString().replaceFirst('Exception: ', '')}';});}
  }
  Future<void> captureLoop(int id) async {
    while(mounted&&watching&&id==run){
      if(paused){await Future<void>.delayed(const Duration(milliseconds:250));continue;}
      final widths=[640,1280,1920], qualities=[45,65,82], delays=[500,250,400];final i=preset;
      try {
        final request=await http.getUrl(Uri.parse('$origin/api/frame?w=${widths[i]}&q=${qualities[i]}'));request.headers.set(HttpHeaders.cookieHeader,cookie!);
        final response=await request.close().timeout(const Duration(seconds:10));
        if(response.statusCode==401){await response.drain<void>(); if(mounted){setState((){watching=false;error='Session ended. Connect again.';});}return;}
        if(response.statusCode!=200){await response.drain<void>();throw Exception('Screen unavailable');}
        final builder=BytesBuilder(copy:false);await for(final chunk in response){builder.add(chunk);}if(!mounted||id!=run)return;
        setState((){frame=builder.takeBytes();error='';});
      }catch(_){if(mounted&&id==run)setState(()=>error='Connection interrupted. Retrying…');}
      await Future<void>.delayed(Duration(milliseconds:delays[i]));
    }
  }
  Future<void> disconnect() async {
    ++run;final saved=cookie;cookie=null;if(landscape){landscape=false;SystemChrome.setPreferredOrientations([]);}if(mounted)setState((){watching=false;frame=null;paused=false;error='';});
    if(saved==null)return;
    try{final request=await http.postUrl(Uri.parse('$origin/api/disconnect'));request.headers.set('Origin',origin);request.headers.set(HttpHeaders.cookieHeader,saved);await (await request.close()).drain<void>();}catch(_){}
  }
  @override void dispose(){++run;host?.kill();events?.cancel();http.close(force:true);pulse.dispose();ip.dispose();port.dispose();code.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    final mobile=MediaQuery.of(context).size.width<700;
    return Scaffold(body:SafeArea(child:LayoutBuilder(builder:(context,c){
      final wide=c.maxWidth>=800;
      return Stack(children:[Positioned(right:-100,top:-180,child:IgnorePointer(child:AnimatedBuilder(animation:pulse,builder:(c,_){return Opacity(opacity:.10+pulse.value*.06,child:Container(width:450,height:450,decoration:const BoxDecoration(shape:BoxShape.circle,gradient:RadialGradient(colors:[coral,Color(0x00ff886c)]))));}))),
        Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:1180),child:SingleChildScrollView(padding:EdgeInsets.symmetric(horizontal:mobile?22:48,vertical:mobile?24:36),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[header(),SizedBox(height:mobile?38:68),if(wide)Row(crossAxisAlignment:CrossAxisAlignment.center,children:[Expanded(flex:5,child:intro(mobile)),const SizedBox(width:55),Expanded(flex:5,child:mainCard())]) else Column(crossAxisAlignment:CrossAxisAlignment.start,children:[intro(mobile),const SizedBox(height:32),mainCard()]),const SizedBox(height:28),footer()]))))
      ]);
    })));
  }
  Widget header()=>Row(children:[ClipRRect(borderRadius:BorderRadius.circular(13),child:Image.asset('assets/icon.png',width:42,height:42)),const SizedBox(width:12),const Text('L U M A L I N K',style:TextStyle(fontSize:13,fontWeight:FontWeight.w800)),const Spacer(),TextButton.icon(onPressed:widget.toggleNight,icon:Icon(widget.night?Icons.light_mode_outlined:Icons.nightlight_round,size:18),label:Text(widget.night?'Dark':'Night'),style:TextButton.styleFrom(foregroundColor:cream))]);
  Widget intro(bool mobile)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Row(children:[Icon(Icons.wifi_rounded,color:coral,size:18),SizedBox(width:9),Text('YOUR SCREEN, CLOSER',style:TextStyle(color:coral,letterSpacing:2,fontSize:12,fontWeight:FontWeight.w800))]),const SizedBox(height:22),Text(windows?'A window to\nyour world.':'Your desktop,\nwithin reach.',style:TextStyle(fontSize:mobile?43:58,height:1.02,letterSpacing:-2,fontWeight:FontWeight.w800,color:cream)),const SizedBox(height:20),Text(windows?'Share your screen with your phone over your own Wi-Fi. You decide who gets in.':'One small connection. Your Windows screen, right in your hands.',style:TextStyle(fontSize:mobile?16:18,height:1.55,color:const Color(0xffc6b5c5))),const SizedBox(height:24),const Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(Icons.shield_outlined,color:coral,size:19),SizedBox(width:10),Expanded(child:Text('View-only access. Your PC approves every connection.',style:TextStyle(color:Color(0xffc6b5c5),height:1.4)))]),const SizedBox(height:28),AnimatedBuilder(animation:pulse,builder:(context,child)=>CustomPaint(foregroundPainter:SignalPainter(MediaQuery.of(context).disableAnimations ? .5 : pulse.value),child:child),child:Container(height:112,decoration:BoxDecoration(borderRadius:BorderRadius.circular(24),gradient:const LinearGradient(colors:[Color(0xff392137),Color(0xff241727)]),border:Border.all(color:const Color(0xff59404d))),child:const Row(mainAxisAlignment:MainAxisAlignment.spaceAround,children:[SignalDevice(icon:Icons.desktop_windows_rounded,label:'WINDOWS'),SizedBox(width:70),SignalDevice(icon:Icons.phone_android_rounded,label:'ANDROID')]))) ]);
  Widget mainCard()=>AnimatedSwitcher(duration:const Duration(milliseconds:350),switchInCurve:Curves.easeOutCubic,transitionBuilder:(child,a)=>FadeTransition(opacity:a,child:SlideTransition(position:Tween<Offset>(begin:const Offset(0,.04),end:Offset.zero).animate(a),child:child)),child:windows?windowsCard():watching?viewerCard():connectCard());
  Widget shell({required Key key,required Widget child})=>Container(key:key,padding:const EdgeInsets.all(24),decoration:BoxDecoration(color:widget.night?const Color(0xff191829):const Color(0xff29192f),borderRadius:BorderRadius.circular(28),border:Border.all(color:const Color(0xff4a3047)),boxShadow:const [BoxShadow(color:Color(0x33000000),blurRadius:45,offset:Offset(0,16))]),child:child);
  Widget sectionTitle(IconData icon,String label)=>Row(children:[Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:const Color(0xff493044),borderRadius:BorderRadius.circular(13)),child:Icon(icon,color:coral,size:20)),const SizedBox(width:12),Expanded(child:Text(label,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w700)))]);
  Widget field(String label,TextEditingController controller,String placeholder,{bool numbers=false,int? length})=>Padding(padding:const EdgeInsets.only(top:16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(label,style:const TextStyle(fontSize:13,color:Color(0xffd4c0cb),fontWeight:FontWeight.w600)),const SizedBox(height:8),TextField(controller:controller,enabled:!sharing&&!connecting,keyboardType:numbers?(identical(controller,ip)?const TextInputType.numberWithOptions(decimal:true):TextInputType.number):TextInputType.text,maxLength:length,inputFormatters:length==null?null:[FilteringTextInputFormatter.digitsOnly],style:const TextStyle(color:cream),decoration:InputDecoration(counterText:'',hintText:placeholder,hintStyle:const TextStyle(color:Color(0xff8e7d8d)),filled:true,fillColor:const Color(0xff1a0e22),contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:16),border:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:BorderSide.none),focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:const BorderSide(color:coral))))]));
  Widget message()=>error.isEmpty?const SizedBox.shrink():Padding(padding:const EdgeInsets.only(top:14),child:Text(error,style:const TextStyle(color:Color(0xffffc4b2),height:1.4)));
  Widget mainButton(String title,VoidCallback? action,{bool busy=false,IconData icon=Icons.arrow_forward_rounded})=>MotionButton(title:title,action:action,busy:busy,icon:icon);
  Widget windowsCard()=>shell(key:const ValueKey('windows'),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[sectionTitle(Icons.desktop_windows_rounded,'Windows host'),const SizedBox(height:22),Text(sharing?'Ready for your phone':'Make your screen available',style:const TextStyle(fontSize:23,fontWeight:FontWeight.w800,letterSpacing:-.5)),const SizedBox(height:8),Text(sharing?'Enter this address and code on your phone.':'Choose your Wi-Fi address and start sharing.',style:const TextStyle(color:Color(0xffc6b5c5),height:1.45)),field('PC Wi-Fi address',ip,'192.168.1.10'),field('Port',port,'8765',numbers:true),if(hint.isNotEmpty&&!sharing)Padding(padding:const EdgeInsets.only(top:10),child:Text(hint,style:const TextStyle(fontSize:12,color:Color(0xffc6b5c5)))),if(sharing)...[const SizedBox(height:22),Container(width:double.infinity,padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:const Color(0xff1a0e22),borderRadius:BorderRadius.circular(16)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('PAIRING CODE',style:TextStyle(color:coral,fontSize:11,letterSpacing:1.5,fontWeight:FontWeight.w800)),const SizedBox(height:6),Text(hostCode,style:const TextStyle(fontSize:32,letterSpacing:7,fontWeight:FontWeight.w800)),Text(origin,style:const TextStyle(color:Color(0xffc6b5c5)))]))],message(),const SizedBox(height:18),mainButton(sharing?'Stop sharing':'Start sharing',sharing?stopHost:(starting?null:startHost),busy:starting,icon:sharing?Icons.stop_circle_outlined:Icons.wifi_tethering_rounded)]));
  Widget connectCard()=>shell(key:const ValueKey('connect'),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[sectionTitle(Icons.phone_android_rounded,'Connect to your PC'),const SizedBox(height:22),const Text('Let’s find your screen.',style:TextStyle(fontSize:23,fontWeight:FontWeight.w800)),const SizedBox(height:8),const Text('Use the address and code shown on Windows.',style:TextStyle(color:Color(0xffc6b5c5))),field('PC Wi-Fi address',ip,'192.168.1.10',numbers:true),field('Port',port,'8765',numbers:true),field('Pairing code',code,'000000',numbers:true,length:6),message(),const SizedBox(height:18),mainButton('Request access',connecting?null:pair,busy:connecting)]));
  Widget viewerCard()=>shell(key:const ValueKey('viewer'),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[sectionTitle(Icons.sensors_rounded,'Your screen'),const SizedBox(height:16),Container(width:double.infinity,clipBehavior:Clip.antiAlias,decoration:BoxDecoration(color:Colors.black,borderRadius:BorderRadius.circular(16)),child:frame==null?const SizedBox(height:200,child:Center(child:Text('Waiting for your screen…',style:TextStyle(color:Colors.white70)))):Image.memory(frame!,gaplessPlayback:true,fit:BoxFit.contain)),message(),const SizedBox(height:16),const Text('IMAGE QUALITY',style:TextStyle(color:Color(0xffc6b5c5),fontSize:12,letterSpacing:1.3,fontWeight:FontWeight.w700)),const SizedBox(height:8),Wrap(spacing:8,children:List.generate(3,(i)=>ChoiceChip(label:Text(['Data saver','Balanced','Sharper'][i]),selected:preset==i,onSelected:(_)=>setState(()=>preset=i)))),const SizedBox(height:12),Wrap(spacing:8,runSpacing:8,children:[OutlinedButton.icon(onPressed:()=>setState(()=>paused=!paused),icon:Icon(paused?Icons.play_arrow:Icons.pause),label:Text(paused?'Resume':'Pause')),OutlinedButton.icon(onPressed:(){landscape=!landscape;SystemChrome.setPreferredOrientations(landscape?[DeviceOrientation.landscapeLeft,DeviceOrientation.landscapeRight]:[]);setState((){});},icon:const Icon(Icons.screen_rotation),label:Text(landscape?'Auto rotate':'Landscape')),OutlinedButton.icon(onPressed:disconnect,icon:const Icon(Icons.link_off),label:const Text('Disconnect'))]) ]));
  Widget footer()=>const Text('TRUSTED WI-FI ONLY  ·  UNENCRYPTED CONNECTION  ·  VIEW ONLY',style:TextStyle(color:Color(0xffa993a7),fontSize:11,letterSpacing:1.1,height:1.5));
}


class SignalDevice extends StatelessWidget {
  final IconData icon; final String label;
  const SignalDevice({super.key,required this.icon,required this.label});
  @override Widget build(BuildContext context)=>Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(icon,color:cream,size:28),const SizedBox(height:8),Text(label,style:const TextStyle(color:Color(0xffd5bcca),fontSize:10,letterSpacing:1.4,fontWeight:FontWeight.w800))]);
}
class SignalPainter extends CustomPainter {
  final double phase; SignalPainter(this.phase);
  @override void paint(Canvas canvas,Size size){
    final center=Offset(size.width/2,size.height/2-6);
    final paint=Paint()..color=coral.withOpacity(.20+phase*.20)..style=PaintingStyle.stroke..strokeWidth=1.5;
    for(final radius in <double>[12,23,34]){canvas.drawCircle(center,radius+phase*3,paint);}
    canvas.drawCircle(center,4,Paint()..color=coral);
    canvas.drawLine(Offset(size.width*.22,center.dy),Offset(center.dx-40,center.dy),paint);
    canvas.drawLine(Offset(center.dx+40,center.dy),Offset(size.width*.78,center.dy),paint);
  }
  @override bool shouldRepaint(covariant SignalPainter oldDelegate)=>phase!=oldDelegate.phase;
}
class MotionButton extends StatefulWidget {
  final String title; final VoidCallback? action; final bool busy; final IconData icon;
  const MotionButton({super.key,required this.title,required this.action,required this.busy,required this.icon});
  @override State<MotionButton> createState()=>_MotionButtonState();
}
class _MotionButtonState extends State<MotionButton> {
  bool pressed=false;
  @override Widget build(BuildContext context)=>GestureDetector(onTapDown:(_){if(widget.action!=null)setState(()=>pressed=true);},onTapUp:(_)=>setState(()=>pressed=false),onTapCancel:()=>setState(()=>pressed=false),child:AnimatedScale(scale:pressed ? .97 : 1,duration:Duration(milliseconds:MediaQuery.of(context).disableAnimations?0:130),curve:Curves.easeOutCubic,child:SizedBox(width:double.infinity,height:54,child:FilledButton.icon(onPressed:widget.action,icon:widget.busy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2,color:Color(0xff29131f))):Icon(widget.icon,size:19),label:Text(widget.title,style:const TextStyle(fontWeight:FontWeight.w800)),style:FilledButton.styleFrom(backgroundColor:coral,foregroundColor:const Color(0xff29131f),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(15)))))));
}
