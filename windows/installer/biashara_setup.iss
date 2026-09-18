; ============================================================================
;  Biashara Yangu — INSTALLEUR WINDOWS (Inno Setup)
; ----------------------------------------------------------------------------
;  Produit `biashara-yangu-setup.exe` : un vrai assistant d'installation
;  (Suivant → Suivant → Terminer) avec raccourcis Menu Démarrer / Bureau et
;  désinstalleur, au lieu d'un simple dossier à extraire.
;
;  Compilation (CI ou locale) :
;      ISCC.exe /DAppVersion=1.2.0 windows\installer\biashara_setup.iss
;  Résultat : windows\installer\dist\biashara-yangu-setup.exe
;
;  ⚠️ Les fichiers embarqués viennent de
;     build\windows\x64\runner\Release\ (exe + data\ + DLL dont sqlite3.dll) :
;     compiler le projet Windows AVANT de lancer Inno Setup.
; ============================================================================

#ifndef AppVersion
  #define AppVersion "1.2.0"
#endif

[Setup]
; Identifiant unique et STABLE de l'application (ne jamais le changer :
; il sert à Windows pour reconnaître les mises à jour par-dessus).
AppId={{7C4B1D2E-9F3A-4E5B-8A6C-1D2E3F4A5B6C}
AppName=Biashara Yangu
AppVersion={#AppVersion}
AppVerName=Biashara Yangu {#AppVersion}
AppPublisher=La Perle
DefaultDirName={autopf}\Biashara Yangu
DefaultGroupName=Biashara Yangu
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=biashara-yangu-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\biashara_yangu.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Installation sans droits administrateur par défaut ; l'utilisateur peut
; choisir « pour tous les utilisateurs » (UAC) s'il le souhaite.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Toute la compilation Windows : biashara_yangu.exe, data\, sqlite3.dll…
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Biashara Yangu"; Filename: "{app}\biashara_yangu.exe"
Name: "{group}\{cm:UninstallProgram,Biashara Yangu}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Biashara Yangu"; Filename: "{app}\biashara_yangu.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\biashara_yangu.exe"; Description: "{cm:LaunchProgram,Biashara Yangu}"; Flags: nowait postinstall skipifsilent
