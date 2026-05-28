#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  JAR Remasterizer V6 — Build APK Android (100% Offline)
#  Execute no terminal do GitHub Codespaces
#  Uso: bash build_apk.sh
# ═══════════════════════════════════════════════════════════════════════
set -e

# ── Cores para output ────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
step()    { echo -e "\n${BOLD}${GREEN}▶ $1${NC}"; }

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║      JAR Remasterizer V6 — APK Builder               ║"
echo "║      Android WebView · 100% Offline                  ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Variáveis de configuração ────────────────────────────────────────
PROJECT_DIR="$HOME/JarRemasterizer"
ANDROID_HOME="$HOME/android-sdk"
BUILD_TOOLS_VERSION="34.0.0"
PLATFORM_VERSION="34"
GRADLE_VERSION="8.4"
APP_ID="com.remasterizer.jar"
APP_NAME="JAR Remasterizer"
VERSION_CODE="6"
VERSION_NAME="6.0"
MIN_SDK="24"
TARGET_SDK="34"

# ── 1. Dependências do sistema ───────────────────────────────────────
step "Instalando dependências do sistema"
sudo apt-get update -qq
sudo apt-get install -y -qq openjdk-17-jdk wget unzip curl python3 2>/dev/null
export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
export PATH="$JAVA_HOME/bin:$PATH"
java -version 2>&1 | head -1
success "Java instalado"

# ── 2. Android SDK ───────────────────────────────────────────────────
step "Instalando Android SDK"
mkdir -p "$ANDROID_HOME/cmdline-tools"
if [ ! -f "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
  info "Baixando Android Command Line Tools..."
  CMDTOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
  wget -q --show-progress "$CMDTOOLS_URL" -O /tmp/cmdtools.zip
  unzip -q /tmp/cmdtools.zip -d /tmp/cmdtools_tmp
  mv /tmp/cmdtools_tmp/cmdline-tools "$ANDROID_HOME/cmdline-tools/latest"
  rm -rf /tmp/cmdtools.zip /tmp/cmdtools_tmp
  success "Android Command Line Tools instalados"
else
  success "Android SDK já instalado"
fi

export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/$BUILD_TOOLS_VERSION:$PATH"

info "Aceitando licenças e instalando SDK components..."
yes | sdkmanager --licenses > /dev/null 2>&1 || true
sdkmanager "platform-tools" "platforms;android-$PLATFORM_VERSION" "build-tools;$BUILD_TOOLS_VERSION" > /dev/null 2>&1
success "Android SDK $PLATFORM_VERSION + Build Tools $BUILD_TOOLS_VERSION instalados"

# ── 3. Gradle ────────────────────────────────────────────────────────
step "Instalando Gradle $GRADLE_VERSION"
GRADLE_DIR="$HOME/gradle-$GRADLE_VERSION"
if [ ! -f "$GRADLE_DIR/bin/gradle" ]; then
  wget -q --show-progress "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" -O /tmp/gradle.zip
  unzip -q /tmp/gradle.zip -d "$HOME"
  rm /tmp/gradle.zip
  success "Gradle $GRADLE_VERSION instalado"
else
  success "Gradle $GRADLE_VERSION já instalado"
fi
export PATH="$GRADLE_DIR/bin:$PATH"
gradle --version | head -1

# ── 4. Baixar dependências offline (JSZip + fontes) ──────────────────
step "Baixando dependências para uso offline"

OFFLINE_DIR="/tmp/offline_deps"
mkdir -p "$OFFLINE_DIR"

# JSZip 3.10.1
info "Baixando JSZip 3.10.1..."
wget -q "https://cdnjs.cloudflare.com/ajax/libs/jszip/3.10.1/jszip.min.js" \
     -O "$OFFLINE_DIR/jszip.min.js"
success "JSZip baixado"

# Fontes Google (Inter, Space Grotesk, JetBrains Mono) como Base64
info "Baixando e convertendo fontes para Base64..."

# Função para baixar fonte e converter para base64
download_font_b64() {
  local URL="$1"
  local OUT="$2"
  wget -q "$URL" -O "$OUT" 2>/dev/null && success "Fonte: $(basename $URL)" || warn "Falha ao baixar $(basename $URL) — será usada fallback"
}

mkdir -p "$OFFLINE_DIR/fonts"
# Inter (subset latina essencial — wght 400)
download_font_b64 "https://fonts.gstatic.com/s/inter/v13/UcCO3FwrK3iLTeHuS_fvQtMwCp50KnMw2boKoduKmMEVuLyfAZ9hiA.woff2" "$OFFLINE_DIR/fonts/inter-400.woff2" || true
download_font_b64 "https://fonts.gstatic.com/s/spacegrotesk/v16/V8mQoQDjQSkFtoMM3T6r8E7mF71Q-gozwSa7benBEm2UiQVBaQ.woff2" "$OFFLINE_DIR/fonts/spacegrotesk-700.woff2" || true
download_font_b64 "https://fonts.gstatic.com/s/jetbrainsmono/v18/tDbY2o-flEEny0FZhsfKu5WU4zr3E_BX0PnT8RD8yKxTOlOV.woff2" "$OFFLINE_DIR/fonts/jetbrainsmono-400.woff2" || true

success "Dependências offline prontas"

# ── 5. Criar HTML offline (inlining de todas as dependências) ────────
step "Gerando HTML completamente offline (sem dependências externas)"

# Converte arquivo para base64 URI
b64_uri() {
  local FILE="$1"
  local MIME="$2"
  if [ -f "$FILE" ]; then
    echo "data:${MIME};base64,$(base64 -w 0 < "$FILE")"
  else
    echo ""
  fi
}

JSZIP_CONTENT=$(cat "$OFFLINE_DIR/jszip.min.js")

# URIs base64 das fontes
INTER_URI=$(b64_uri "$OFFLINE_DIR/fonts/inter-400.woff2" "font/woff2")
SPACEGROTESK_URI=$(b64_uri "$OFFLINE_DIR/fonts/spacegrotesk-700.woff2" "font/woff2")
JETBRAINS_URI=$(b64_uri "$OFFLINE_DIR/fonts/jetbrainsmono-400.woff2" "font/woff2")

# Gera o CSS de fontes inline (offline)
FONT_CSS=""
if [ -n "$INTER_URI" ]; then
  FONT_CSS="${FONT_CSS}
@font-face {
  font-family: 'Inter';
  font-style: normal;
  font-weight: 400;
  src: url('${INTER_URI}') format('woff2');
}"
fi
if [ -n "$SPACEGROTESK_URI" ]; then
  FONT_CSS="${FONT_CSS}
@font-face {
  font-family: 'Space Grotesk';
  font-style: normal;
  font-weight: 700;
  src: url('${SPACEGROTESK_URI}') format('woff2');
}"
fi
if [ -n "$JETBRAINS_URI" ]; then
  FONT_CSS="${FONT_CSS}
@font-face {
  font-family: 'JetBrains Mono';
  font-style: normal;
  font-weight: 400;
  src: url('${JETBRAINS_URI}') format('woff2');
}"
fi

info "Construindo HTML offline..."

# Lê o HTML original e realiza as substituições
HTML_SRC="/tmp/Remaster_Java_DS_V6.html"

# Verifica se o HTML foi colocado na pasta correta
if [ ! -f "$HTML_SRC" ]; then
  # Procura em locais comuns do Codespace
  for LOC in \
    "$HOME/Remaster_Java_DS_V6.html" \
    "$HOME/workspace/Remaster_Java_DS_V6.html" \
    "/workspaces/Remaster_Java_DS_V6.html" \
    "/workspaces/*/Remaster_Java_DS_V6.html" \
    "$(find /workspaces $HOME -name 'Remaster_Java_DS_V6.html' 2>/dev/null | head -1)"
  do
    if [ -f "$LOC" ]; then
      HTML_SRC="$LOC"
      break
    fi
  done
fi

if [ ! -f "$HTML_SRC" ]; then
  echo ""
  echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${RED}║  ATENÇÃO: HTML não encontrado automaticamente        ║${NC}"
  echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "Por favor, coloque o arquivo ${BOLD}Remaster_Java_DS_V6.html${NC} em:"
  echo -e "  ${YELLOW}/tmp/Remaster_Java_DS_V6.html${NC}"
  echo ""
  echo "No terminal do Codespace, execute:"
  echo -e "  ${CYAN}cp /caminho/do/arquivo/Remaster_Java_DS_V6.html /tmp/${NC}"
  echo ""
  read -p "Pressione Enter após copiar o arquivo..."
  HTML_SRC="/tmp/Remaster_Java_DS_V6.html"
fi

if [ ! -f "$HTML_SRC" ]; then
  echo -e "${RED}[ERRO] Arquivo HTML não encontrado. Abortando.${NC}"
  exit 1
fi

success "HTML encontrado: $HTML_SRC"

# Usa Python para fazer o inline do HTML (mais robusto que sed para arquivos grandes)
python3 << PYEOF
import re, base64, os

html_src = open("$HTML_SRC", "r", encoding="utf-8").read()

# 1. Remove o @import do Google Fonts e o <script src=...> do JSZip
html_src = re.sub(r"@import url\('https://fonts\.googleapis\.com[^']*'\);?\s*\n?", "", html_src)
html_src = re.sub(r'<script\s+src="https://cdnjs\.cloudflare\.com/[^"]*jszip[^"]*"[^>]*></script>', "", html_src)

# 2. Injeta fontes offline logo após o <style>
font_css = """$FONT_CSS"""
html_src = html_src.replace("<style>", "<style>\n" + font_css + "\n", 1)

# 3. Injeta JSZip inline antes do </head>
jszip_js = open("$OFFLINE_DIR/jszip.min.js", "r", encoding="utf-8").read()
jszip_tag = '<script id="jszip-inline">\n' + jszip_js + '\n</script>\n'
html_src = html_src.replace("</head>", jszip_tag + "</head>", 1)

# 4. Adiciona meta offline + viewport seguro para Android WebView
android_meta = '''<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="theme-color" content="#04040c">'''
html_src = html_src.replace('<meta name="viewport"', android_meta + '\n<meta name="viewport"', 1)

# Salva o resultado
out_path = "/tmp/index_offline.html"
with open(out_path, "w", encoding="utf-8") as f:
    f.write(html_src)

size_kb = os.path.getsize(out_path) / 1024
print(f"  HTML offline gerado: {out_path} ({size_kb:.0f} KB)")

# Verifica que não restaram referências externas
ext_refs = re.findall(r'(?:src|href)=["\']https?://[^"\']+["\']', html_src)
ext_refs = [r for r in ext_refs if 'data:' not in r]
if ext_refs:
    print(f"  AVISO: ainda há {len(ext_refs)} referência(s) externa(s):")
    for r in ext_refs[:5]:
        print(f"    {r}")
else:
    print("  Verificação: ZERO referências externas. App 100% offline!")
PYEOF

success "HTML offline gerado em /tmp/index_offline.html"

# ── 6. Estrutura do projeto Android ─────────────────────────────────
step "Criando estrutura do projeto Android"

rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/app/src/main/java/com/remasterizer"
mkdir -p "$PROJECT_DIR/app/src/main/assets"
mkdir -p "$PROJECT_DIR/app/src/main/res/mipmap-hdpi"
mkdir -p "$PROJECT_DIR/app/src/main/res/mipmap-mdpi"
mkdir -p "$PROJECT_DIR/app/src/main/res/mipmap-xhdpi"
mkdir -p "$PROJECT_DIR/app/src/main/res/mipmap-xxhdpi"
mkdir -p "$PROJECT_DIR/app/src/main/res/mipmap-xxxhdpi"
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
mkdir -p "$PROJECT_DIR/app/src/main/res/xml"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# Copia HTML offline para assets
cp /tmp/index_offline.html "$PROJECT_DIR/app/src/main/assets/index.html"
success "HTML copiado para assets"

# ── 6a. Ícone do app (gerado via Python) ────────────────────────────
info "Gerando ícone do app..."
python3 << 'PYEOF'
import struct, zlib, os

def write_png(filename, size, bg_color, fg_color):
    """Gera um PNG simples com gradiente (ícone do app)"""
    w, h = size, size
    raw_rows = []
    for y in range(h):
        row = bytearray([0])  # filter byte
        for x in range(w):
            # Gradiente radial simulando o header-icon do app
            cx, cy = w/2, h/2
            dist = ((x-cx)**2 + (y-cy)**2) ** 0.5
            r_max = w * 0.5
            t = min(1.0, dist / r_max)
            r = int(bg_color[0]*(1-t) + fg_color[0]*t)
            g = int(bg_color[1]*(1-t) + fg_color[1]*t)
            b = int(bg_color[2]*(1-t) + fg_color[2]*t)
            # Rounded corners (corner radius ~22%)
            cr = w * 0.22
            inCorner = False
            for cx2, cy2 in [(cr,cr),(w-cr,cr),(cr,h-cr),(w-cr,h-cr)]:
                if ((x-cx2)**2+(y-cy2)**2)**0.5 > cr and x < cr*1 and y < cr*1 and abs(x-cx2) < cr and abs(y-cy2) < cr:
                    inCorner = True
            a = 0 if inCorner else 255
            row.extend([r, g, b, a])
        raw_rows.append(bytes(row))
    raw = b''.join(raw_rows)
    compressed = zlib.compress(raw, 9)
    def chunk(name, data):
        c = name + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    ihdr_data = struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)
    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', ihdr_data)
    png += chunk(b'IDAT', compressed)
    png += chunk(b'IEND', b'')
    with open(filename, 'wb') as f:
        f.write(png)

# Cor do gradiente: #5a48c8 → #9d8fff (cor do header-icon)
bg = (90, 72, 200)   # #5a48c8
fg = (157, 143, 255) # #9d8fff

sizes = {
    'mdpi':    48,
    'hdpi':    72,
    'xhdpi':   96,
    'xxhdpi':  144,
    'xxxhdpi': 192,
}
base = "/root/JarRemasterizer/app/src/main/res"
for dpi, size in sizes.items():
    path = f"{base}/mipmap-{dpi}/ic_launcher.png"
    write_png(path, size, bg, fg)
    print(f"  Ícone {dpi} ({size}x{size}px) gerado")
PYEOF
success "Ícones gerados"

# ── 6b. settings.gradle ──────────────────────────────────────────────
cat > "$PROJECT_DIR/settings.gradle" << 'EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "JarRemasterizer"
include ':app'
EOF

# ── 6c. build.gradle (raiz) ──────────────────────────────────────────
cat > "$PROJECT_DIR/build.gradle" << EOF
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:8.2.2'
    }
}
EOF

# ── 6d. app/build.gradle ─────────────────────────────────────────────
cat > "$PROJECT_DIR/app/build.gradle" << EOF
plugins {
    id 'com.android.application'
}

android {
    namespace '${APP_ID}'
    compileSdk ${PLATFORM_VERSION}

    defaultConfig {
        applicationId "${APP_ID}"
        minSdk ${MIN_SDK}
        targetSdk ${TARGET_SDK}
        versionCode ${VERSION_CODE}
        versionName "${VERSION_NAME}"
    }

    buildTypes {
        debug {
            debuggable true
        }
        release {
            minifyEnabled false
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_11
        targetCompatibility JavaVersion.VERSION_11
    }
}

dependencies {
    implementation 'androidx.appcompat:appcompat:1.6.1'
}
EOF

# ── 6e. gradle/wrapper/gradle-wrapper.properties ─────────────────────
cat > "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.properties" << EOF
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF

cat > "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.jar" << 'EOF'
EOF
# Usa gradle diretamente (sem wrapper) — mais simples no Codespace

# ── 6f. AndroidManifest.xml ──────────────────────────────────────────
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <!-- Não precisa de internet — app 100% offline -->

    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="${APP_NAME}"
        android:theme="@style/AppTheme"
        android:hardwareAccelerated="true">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:configChanges="orientation|screenSize|keyboardHidden"
            android:screenOrientation="unspecified"
            android:windowSoftInputMode="adjustResize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

    </application>

</manifest>
EOF

# ── 6g. MainActivity.java ────────────────────────────────────────────
cat > "$PROJECT_DIR/app/src/main/java/com/remasterizer/MainActivity.java" << 'EOF'
package com.remasterizer;

import android.app.Activity;
import android.graphics.Color;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

public class MainActivity extends Activity {

    private WebView webView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Status bar escura para combinar com o tema do app (#04040c)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            Window window = getWindow();
            window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
            window.setStatusBarColor(Color.parseColor("#04040c"));
            window.setNavigationBarColor(Color.parseColor("#04040c"));
        }

        // Oculta a action bar nativa
        if (getActionBar() != null) getActionBar().hide();

        // Cria WebView programaticamente
        webView = new WebView(this);
        setContentView(webView);

        // Fundo preto enquanto carrega
        webView.setBackgroundColor(Color.parseColor("#04040c"));

        // ── Configurações do WebView ───────────────────────────────
        WebSettings settings = webView.getSettings();

        // JavaScript obrigatório (a lógica inteira é JS)
        settings.setJavaScriptEnabled(true);

        // Workers: permite que o Blob URL do Worker funcione dentro do WebView
        settings.setAllowFileAccessFromFileURLs(true);
        settings.setAllowUniversalAccessFromFileURLs(true);

        // Storage para possível uso de localStorage no futuro
        settings.setDomStorageEnabled(true);

        // Cache local (garante offline mesmo se o sistema tentar invalidar)
        settings.setCacheMode(WebSettings.LOAD_NO_CACHE);

        // Suporte a OffscreenCanvas e recursos modernos
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            settings.setSafeBrowsingEnabled(false);
        }

        // Viewport e zoom
        settings.setUseWideViewPort(true);
        settings.setLoadWithOverviewMode(true);
        settings.setSupportZoom(false);
        settings.setBuiltInZoomControls(false);
        settings.setDisplayZoomControls(false);

        // Hardware acceleration para processamento de imagens
        settings.setRenderPriority(WebSettings.RenderPriority.HIGH);

        // Algoritmo de layout responsivo
        settings.setLayoutAlgorithm(WebSettings.LayoutAlgorithm.TEXT_AUTOSIZING);

        // ── Clientes do WebView ────────────────────────────────────

        // Impede navegação externa — tudo permanece no webview
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                // Bloqueia qualquer navegação externa
                if (url.startsWith("file://") || url.startsWith("data:") || url.startsWith("blob:")) {
                    return false; // Deixa o WebView processar
                }
                return true; // Bloqueia URLs externas
            }
        });

        // Permite que o app use console.log (útil para debug)
        webView.setWebChromeClient(new WebChromeClient());

        // ── Habilita modo escuro no WebView (Android 10+) ──────────
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // O app já tem fundo escuro no HTML, isso reforça
            webView.getSettings().setForceDark(WebSettings.FORCE_DARK_OFF);
        }

        // ── Carrega o HTML do assets (sem internet) ────────────────
        webView.loadUrl("file:///android_asset/index.html");
    }

    // Botão voltar navega no histórico do WebView
    @Override
    public void onBackPressed() {
        if (webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        webView.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        webView.onResume();
    }

    @Override
    protected void onDestroy() {
        if (webView != null) {
            webView.destroy();
        }
        super.onDestroy();
    }
}
EOF

# ── 6h. res/values/styles.xml ────────────────────────────────────────
cat > "$PROJECT_DIR/app/src/main/res/values/styles.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="AppTheme" parent="android:Theme.Material.NoActionBar">
        <item name="android:windowBackground">#04040c</item>
        <item name="android:colorBackground">#04040c</item>
        <item name="android:statusBarColor">#04040c</item>
        <item name="android:navigationBarColor">#04040c</item>
        <item name="android:windowDrawsSystemBarBackgrounds">true</item>
        <item name="android:windowTranslucentStatus">false</item>
        <item name="android:windowTranslucentNavigation">false</item>
    </style>
</resources>
EOF

# ── 6i. res/values/strings.xml ───────────────────────────────────────
cat > "$PROJECT_DIR/app/src/main/res/values/strings.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">${APP_NAME}</string>
</resources>
EOF

# ── 6j. proguard-rules.pro ───────────────────────────────────────────
cat > "$PROJECT_DIR/app/proguard-rules.pro" << 'EOF'
# Regras ProGuard — não ofusca WebView bridges
-keepclassmembers class * extends android.webkit.WebViewClient {
    public *;
}
EOF

success "Estrutura do projeto criada"

# ── 7. Compilar APK ──────────────────────────────────────────────────
step "Compilando APK"
cd "$PROJECT_DIR"

info "Iniciando build com Gradle..."
gradle assembleDebug \
  -PANDROID_HOME="$ANDROID_HOME" \
  --no-daemon \
  --stacktrace \
  2>&1 | tee /tmp/gradle_build.log | grep -E "(BUILD|ERROR|WARNING|Task|:app)" || true

BUILD_STATUS=${PIPESTATUS[0]}

if [ $BUILD_STATUS -eq 0 ] && [ -f "$PROJECT_DIR/app/build/outputs/apk/debug/app-debug.apk" ]; then
  APK_PATH="$PROJECT_DIR/app/build/outputs/apk/debug/app-debug.apk"
  APK_SIZE=$(du -sh "$APK_PATH" | cut -f1)

  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║              ✅  BUILD CONCLUÍDO!                    ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${BOLD}APK gerado:${NC}  $APK_PATH"
  echo -e "  ${BOLD}Tamanho:${NC}     $APK_SIZE"
  echo ""
  echo -e "${CYAN}Para baixar o APK no Codespace:${NC}"
  echo -e "  1. Abra o painel de arquivos (Explorer)"
  echo -e "  2. Navegue até: ${BOLD}JarRemasterizer/app/build/outputs/apk/debug/${NC}"
  echo -e "  3. Clique com botão direito em ${BOLD}app-debug.apk${NC} → Download"
  echo ""
  echo -e "${YELLOW}Ou use o comando:${NC}"
  echo -e "  ${CYAN}cp \"$APK_PATH\" /workspaces/app-debug.apk${NC}"
  echo ""
  echo -e "${YELLOW}⚠️  Nota:${NC} APK debug — para instalar no Android, ative"
  echo -e "  'Instalar de fontes desconhecidas' nas Configurações do dispositivo."
else
  echo ""
  echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${RED}║              ❌  ERRO NO BUILD                       ║${NC}"
  echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "Log completo em: /tmp/gradle_build.log"
  echo ""
  echo "Últimas linhas do log:"
  tail -30 /tmp/gradle_build.log
  exit 1
fi
