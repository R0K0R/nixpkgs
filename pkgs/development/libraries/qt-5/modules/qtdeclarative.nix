{
  qtModule,
  python3,
  qtbase,
  qtsvg,
}:

qtModule {
  pname = "qtdeclarative";
  propagatedBuildInputs = [
    qtbase
    qtsvg
  ];
  nativeBuildInputs = [ python3 ];
  outputs = [
    "out"
    "dev"
    "bin"
  ];
  postPatch = ''
    # GCC 15 no longer transitively includes <cstdint> via other standard
    # headers, so uint32_t/uint64_t used here are no longer declared.
    sed -i '/#include <QCryptographicHash>/a #include <cstdint>' src/qml/compiler/qv4compiler.cpp
  '';
  preConfigure = ''
    NIX_CFLAGS_COMPILE+=" -DNIXPKGS_QML2_IMPORT_PREFIX=\"$qtQmlPrefix\""
  '';
  configureFlags = [ "-qml-debug" ];
  devTools = [
    "bin/qml"
    "bin/qmlcachegen"
    "bin/qmleasing"
    "bin/qmlimportscanner"
    "bin/qmllint"
    "bin/qmlmin"
    "bin/qmlplugindump"
    "bin/qmlprofiler"
    "bin/qmlscene"
    "bin/qmltestrunner"
  ];
}
