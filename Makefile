export THEOS_DEVICE_IP = localhost
export THEOS_DEVICE_PORT = 2222

build:
	#make -f Makefile.x86_64
	make -f Makefile.arm
	#lipo -create .theos/obj/debug/libsymbolicate.dylib obj/macosx/libsymbolicate.dylib -output libsymbolicate.dylib
	#mv libsymbolicate.dylib obj/libsymbolicate.dylib

clean:
	make -f Makefile.x86_64 clean
	make -f Makefile.arm clean

distclean:
	make -f Makefile.x86_64 distclean
	make -f Makefile.arm distclean

package: build
	make -f Makefile.arm package

sdk:
	make -f Makefile.arm sdk

install:
	make -f Makefile.arm install
