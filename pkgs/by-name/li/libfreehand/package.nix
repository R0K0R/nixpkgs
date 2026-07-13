{
  lib,
  stdenv,
  fetchzip,
  perl,
  pkg-config,
  boost,
  cppunit,
  doxygen,
  gperf,
  icu,
  lcms2,
  librevenge,
  zlib,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "libfreehand";
  version = "0.1.3";

  src = fetchzip {
    url = "https://dev-www.libreoffice.org/src/libfreehand/libfreehand-${finalAttrs.version}.tar.xz";
    hash = "sha256-ZcvG00JP3BoFv1PIeAhZyr7t1zANhTVluBZQqEbWCvY=";
  };

  nativeBuildInputs = [
    # gperf is a build-time code generator (src/lib/tokens.gperf -> tokens.h).
    # In buildInputs it lands on the HOST side, whose bin/ is correctly absent
    # from PATH in cross builds -- autotools' `missing` wrapper then warns
    # "gperf is missing" and continues, producing a broken tokens.h that fails
    # later with "'fhtoken' does not name a type". Native builds don't notice.
    gperf
    perl
    pkg-config
  ];

  buildInputs = [
    boost
    cppunit
    doxygen
    icu
    lcms2
    librevenge
    zlib
  ];

  configureFlags = [ "--disable-werror" ];

  meta = {
    description = "Adobe Freehand import library";
    homepage = "https://wiki.documentfoundation.org/DLP/Libraries/libfreehand";
    license = lib.licenses.mpl20;
    maintainers = [ ];
    platforms = lib.platforms.all;
  };
})
