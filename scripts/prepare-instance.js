const fs = require('fs');
const path = require('path');

const instanceId = process.argv[2] || 'christian_tube';
const rootDir = path.resolve(__dirname, '..');
const instanceDir = path.join(rootDir, 'instances', instanceId);

if (!fs.existsSync(instanceDir)) {
  console.error(`Error: Instance directory '${instanceDir}' does not exist!`);
  process.exit(1);
}

const configPath = path.join(instanceDir, 'config.json');
if (!fs.existsSync(configPath)) {
  console.error(`Error: Config file '${configPath}' not found!`);
  process.exit(1);
}

const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
console.log(`🚀 Preparing PrivateTube engine for instance: ${config.appName} (${config.instanceId})...`);

// 1. Copy config to mobile assets
const mobileAssetsDir = path.join(rootDir, 'apps', 'mobile', 'assets');
fs.mkdirSync(mobileAssetsDir, { recursive: true });
fs.copyFileSync(configPath, path.join(mobileAssetsDir, 'app_config.json'));
console.log(`✅ Synced app_config.json to mobile assets`);

// 2. Copy instance icon to logo.png
const iconSrc = path.join(instanceDir, 'assets', 'icon.png');
if (fs.existsSync(iconSrc)) {
  fs.copyFileSync(iconSrc, path.join(mobileAssetsDir, 'logo.png'));
  console.log(`✅ Synced logo.png to mobile assets`);

  // 3. Copy icon to Android mipmaps
  const resDir = path.join(rootDir, 'apps', 'mobile', 'android', 'app', 'src', 'main', 'res');
  const mipmaps = ['mipmap-mdpi', 'mipmap-hdpi', 'mipmap-xhdpi', 'mipmap-xxhdpi', 'mipmap-xxxhdpi'];
  
  for (const mm of mipmaps) {
    const targetDir = path.join(resDir, mm);
    fs.mkdirSync(targetDir, { recursive: true });
    fs.copyFileSync(iconSrc, path.join(targetDir, 'ic_launcher.png'));
  }
  console.log(`✅ Synced Android launcher icons across all mipmap densities`);
}

// 4. Update Android build.gradle applicationId & app label
const buildGradlePath = path.join(rootDir, 'apps', 'mobile', 'android', 'app', 'build.gradle');
if (fs.existsSync(buildGradlePath)) {
  let buildGradle = fs.readFileSync(buildGradlePath, 'utf8');
  buildGradle = buildGradle.replace(
    /applicationId(\s*=\s*|\s+)["'][^"']+["']/,
    `applicationId "${config.applicationId}"`
  );
  fs.writeFileSync(buildGradlePath, buildGradle, 'utf8');
  console.log(`✅ Updated Android applicationId to: ${config.applicationId}`);
}

// 5. Update AndroidManifest.xml label
const manifestPath = path.join(rootDir, 'apps', 'mobile', 'android', 'app', 'src', 'main', 'AndroidManifest.xml');
if (fs.existsSync(manifestPath)) {
  let manifest = fs.readFileSync(manifestPath, 'utf8');
  manifest = manifest.replace(
    /android:label="[^"]*"/,
    `android:label="${config.appName}"`
  );
  fs.writeFileSync(manifestPath, manifest, 'utf8');
  console.log(`✅ Updated AndroidManifest label to: ${config.appName}`);
}

console.log(`🎉 Instance preparation complete for ${config.appName}!`);
