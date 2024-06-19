# swift-netpbm

This Swift package vends C `libnetpbm` library for image manipulation as `libnetpbm` product. While the `libnetpbm` from the package is fully functional, it is not recommended for direct use in Swift due to compatibility issues. The original `libnetpbm` library is written in a way that does not integrate well with Swift. If there is an error while parsing an image file or during input-output operations, the library may call `exit` or use `longjump`, depending on its initialization. An `exit` call will cause the app to terminate abruptly, resembling a crash. Utilizing `longjump` in Swift results in undefined behavior.

Porting C `libnetpbm` into Swift is work in progress and not yet ready to be used.

Reference to original [Netpbm homepage](https://netpbm.sourceforge.net/doc/).

[Netpbm in Wikipedia](https://en.wikipedia.org/wiki/Netpbm).

[Introduction into libnetpbm](https://netpbm.sourceforge.net/doc/libnetpbm.html).

[Libnetpbm User's Guide](https://netpbm.sourceforge.net/doc/libnetpbm_ug.html) which covers PAM functions recommended to be used.

References for legacy interfaces:

* [pbm Functions](https://netpbm.sourceforge.net/doc/libpbm.html);

* [pgm Functions](https://netpbm.sourceforge.net/doc/libpgm.html);

* [ppm Functions](https://netpbm.sourceforge.net/doc/libppm.html);

* [pnm Functions](https://netpbm.sourceforge.net/doc/libpnm.html).
