// Sign-in and account-deleted (the owner, 22 Oct). The launch's white (day)
// and grey (night) stethoscopes stand over "Stethoscore" where the three mode
// tiles were; the art is private, so only its slot (LaunchArt's names) and a
// stand-in shape are kept here. Apple's button stays black by day and white by
// night; Google's is Google's own branded button with the multicolour G. Both
// keep their makers' colours, outside the ten hexes. Android has no sign-in
// screen and no Google sign-in (android/docs/parity.md), so it gets none.
// The launchopening Swift suite proves the lookup (LaunchArt.names) on Linux;
// the screen is SwiftUI, which only a Mac lays out, so here its source is
// read. The art is added outside this repository, so a CI-built app always
// shows the stand-in; the source names only the art's slots, never where the
// art is kept.
import { readFileSync, existsSync } from 'node:fs';

const repo = new URL('../../', import.meta.url).pathname;
let failed = 0;
function check(label, ok, detail = '') {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : '  | ' + detail}`);
  if (!ok) failed++;
}
const read = (rel) => readFileSync(repo + rel, 'utf8');
const src = read('ios/RedPen/Features/Auth/SignInView.swift');
const mast = src.slice(src.indexOf('private var masthead: some View {'), src.indexOf('private var smallPrint'));
const google = src.slice(src.indexOf('private var googleDoor: some View {'), src.indexOf('/// Apple\'s own button'));
const apple = src.slice(src.indexOf('private var appleDoor: some View {'), src.indexOf('private var localDoor'));

// 1: the launch mark, not the mode tiles
check('the masthead draws the launch mark above the name', /SignInLaunchMark\(\)[\s\S]*Text\(Brand\.name\)/.test(mast));
check('no mode tiles fanned above the name', !/ModeTile\(/.test(src) && !/mastTile|tileAngle|tileLayer/.test(src));
check('the mark is looked up by LaunchArt\'s names, the mode\'s first',
  /LaunchArt\.names\(dark: dark\)\.lazy\.compactMap \{ UIImage\(named: \$0\) \}\.first/.test(src));
check('the mark names only the art\'s slots, found through LaunchArt.names',
  /LaunchLogo\{,-dark\}@\{2,3\}x\.png, *\n *\/\/\/ which UIImage\(named:\) finds through LaunchArt\.names/.test(src));
check('and nothing of where the private art is kept',
  !/Claude-Code|inject_brand_art|1adb11e|brand-art|fed0105|Payload\//.test(src));
check('without the art, a stand-in shape in the ink', /Image\(systemName: "stethoscope"\)[\s\S]{0,200}Color\.wardInkSecondary/.test(src));
check('the private art is not in the public tree',
  !existsSync(repo + 'ios/RedPen/Assets.xcassets/LaunchLogo.imageset') && !existsSync(repo + 'ios/RedPen/Assets.xcassets/LaunchLogo-dark.imageset'));
check('account-deleted is the same screen (PreviewSignIn(deleted: true))', /case "account-deleted":[\s\S]{0,200}PreviewSignIn\(deleted: true\)/.test(read('ios/RedPen/Shared/PreviewExtras.swift')));

// 8: the doors
check('Apple: black by day, white by night', /scheme == \.dark \? \.white : \.black/.test(apple) && /signInWithAppleButtonStyle\(style\)/.test(apple));
check('Google: offered only where the build is set up for it', /if GoogleSignIn\.isConfigured \{ googleDoor \}/.test(src));
check('Google: the multicolour G, not a globe', /GoogleG\(\)/.test(google) && !/"globe"/.test(src));
check('Google: "Sign in with Google" in Google\'s theme, with its hairline',
  /"Sign in with Google"/.test(google) && /theme\.fill/.test(google) && /strokeBorder\(theme\.stroke, lineWidth: 1\)/.test(google) && /theme\.text/.test(google));
check('Google: its light and dark themes are Google\'s own colours',
  /dark \? 0x131314 : 0xFFFFFF/.test(src) && /dark \? 0x8E918F : 0x747775/.test(src) && /dark \? 0xE3E3E3 : 0x1F1F1F/.test(src));
check('Google: the G in its four colours',
  ['0xEA4335', '0x4285F4', '0xFBBC05', '0x34A853'].every((h) => src.includes(h)));
check('Google: the label at Google\'s 14 pt, scaled with Dynamic Type',
  /static let labelSize: CGFloat = 14/.test(src) && /\.scaledFont\(GoogleButtonTheme\.labelSize, relativeTo: \.body, weight: \.medium\)/.test(google));
check('Google: Apple\'s height and corners beside it', /\.frame\(height: 56\)/.test(google) && /SignInView\.door/.test(google));

// Android: none to add
const parity = read('android/docs/parity.md');
check('Android has no sign-in screen to put a Google button on',
  !/GoogleSignIn|signInWithGoogle/.test(read('android/app/src/main/java/com/stethoscore/app/ui/StethoscoreApp.kt')) && /sign-in/i.test(parity));

if (failed) { console.log(`\n${failed} FAILED`); process.exit(1); }
console.log('\nsign-in doors: all checks pass');
