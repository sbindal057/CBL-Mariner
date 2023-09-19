#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

#
# Building packages in chroot with temporary toolchain packages
#

set -x

echo Calling script to create files:

sh /tools/toolchain_initial_chroot_setup.sh
#exec /tools/bin/bash --login +h

echo Now, running the final build steps in chroot inside container

# Set BUILD_TARGET
case $(uname -m) in
    x86_64)
        BUILD_TARGET=x86_64-pc-linux-gnu
    ;;
    aarch64)
        BUILD_TARGET=aarch64-unknown-linux-gnu
    ;;
esac

echo Configuring files under /var/log
touch /var/log/{btmp,lastlog,faillog,wtmp}
chgrp -v utmp /var/log/lastlog
chmod -v 664  /var/log/lastlog
chmod -v 600  /var/log/btmp

echo Printing debug info
echo Path: $PATH
ls -la /bin/bash
ls -la /bin/sh
ls -la /bin
ls -la /tools
ls -la /tools/bin
ls -la /tools/lib
ls -la /lib64
ls /tools/bin
ls /tools/sbin
ls /bin
ls /
ls /usr/bin
ls /usr/sbin
ls -la /usr/sbin
ls -la /usr/bin
ls -la /bin/bash
ls -la /bin/sh
echo sanity check - raw toolchain - before building - gcc -v
find / -name ld-linux-x86-64.so.2
ls -la /lib64/ld-linux-x86-64.so.2
ls -la /tools/lib/ld-linux-x86-64.so.2
ls -la /lib64
ls -la /lib64/ld-lsb-x86-64.so.3
ls -la /lib64/ld-linux-x86-64.so.2
file /tools/bin/gcc
gcc -v
echo Finished printing debug info

set -e
#
# Start building packages
#
cd /sources

KERNEL_VERSION="5.15.48.1"
echo Linux-${KERNEL_VERSION} API Headers
tar xf kernel-${KERNEL_VERSION}.tar.gz
pushd CBL-Mariner-Linux-Kernel-rolling-lts-mariner-2-${KERNEL_VERSION}
make mrproper
make headers
cp -rv usr/include/* /usr/include
popd
rm -rf CBL-Mariner-Linux-Kernel-rolling-lts-mariner-2-${KERNEL_VERSION}
touch /logs/status_kernel_headers_complete

echo 6.8. Man-pages-5.02
tar xf man-pages-5.02.tar.xz
pushd man-pages-5.02
make install
popd
rm -rf man-pages-5.02
touch /logs/status_man_pages_complete

echo glibc-2.35
tar xf glibc-2.35.tar.xz
pushd glibc-2.35
patch -Np1 -i ../glibc-2.35-fhs-1.patch
ln -sfv /tools/lib/gcc /usr/lib
ls -la /usr/lib/gcc/
case $(uname -m) in
    x86_64)
        GCC_INCDIR=/usr/lib/gcc/$BUILD_TARGET/11.2.0/include
    ;;
    aarch64)
        GCC_INCDIR=/usr/lib/gcc/$BUILD_TARGET/11.2.0/include
    ;;
esac
rm -f /usr/include/limits.h
mkdir -v build
cd       build
CC="gcc -isystem $GCC_INCDIR -isystem /usr/include" \
../configure --prefix=/usr                          \
             --disable-werror                       \
             --enable-kernel=3.2                    \
             --enable-stack-protector=strong        \
             libc_cv_slibdir=/lib

#             libc_cv_ctors_header=yes
# ERROR:
# checking whether to use .ctors/.dtors header and trailer... configure: error: missing __attribute__ ((constructor)) support??
# adding 'libc_cv_ctors_header=yes'
unset GCC_INCDIR
make -j$(nproc)
touch /etc/ld.so.conf
sed '/test-installation/s@$(PERL)@echo not running@' -i ../Makefile
make install
cp -v ../nscd/nscd.conf /etc/nscd.conf
mkdir -pv /var/cache/nscd
cat > /etc/ld.so.conf << "EOF"
# Begin /etc/ld.so.conf
/usr/local/lib
/opt/lib
# Add an include directory
include /etc/ld.so.conf.d/*.conf
EOF
mkdir -pv /etc/ld.so.conf.d
popd
rm -rf glibc-2.35

touch /logs/status_glibc_complete

echo 6.10. Adjusting the Toolchain
find / -name ld-linux-x86-64.so.2
# The final C library was just installed above. Ajust the toolchain to link newly compiled programs with it.
mv -v /tools/bin/{ld,ld-old}
mv -v /tools/$BUILD_TARGET/bin/{ld,ld-old}
mv -v /tools/bin/{ld-new,ld}
ln -sv /tools/bin/ld /tools/$BUILD_TARGET/bin/ld
gcc -dumpspecs | sed -e 's@/tools@@g'                   \
    -e '/\*startfile_prefix_spec:/{n;s@.*@/usr/lib/ @}' \
    -e '/\*cpp:/{n;s@$@ -isystem /usr/include@}' >      \
    `dirname $(gcc --print-libgcc-file-name)`/specs
# Sanity check for adjusted toolchain:
echo sanity check - raw toolchain - adjusting the toolchain
set +e
echo 'int main(){}' > dummy.c
cc dummy.c -v -Wl,--verbose &> dummy.log
sleep 3
sync
# This sets errorlevel..
readelf -l a.out | grep ': /lib'
case $(uname -m) in
  x86_64)
    echo Expected: '[Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]'
  ;;
  aarch64)
    echo Expected: '[Requesting program interpreter: /lib/ld-linux-aarch64.so.1]'
  ;;
esac
readelf -l a.out
echo End of readelf output
grep -o '/usr/lib.*/crt[1in].*succeeded' dummy.log
echo Expected output: 'Three similar lines:  /usr/lib/../lib/crt1.o succeeded ...'
# Expected output:
# /usr/lib/../lib/crt1.o succeeded
# /usr/lib/../lib/crti.o succeeded
# /usr/lib/../lib/crtn.o succeeded
grep -B1 '^ /usr/include' dummy.log
# Expected output:
# #include <...> search starts here:
#  /usr/include
grep 'SEARCH.*/usr/lib' dummy.log |sed 's|; |\n|g'
echo Expected output: 'SEARCH_DIR("/usr/lib") SEARCH_DIR("/lib")'
# Expected output:
# SEARCH_DIR("/usr/lib")
# SEARCH_DIR("/lib")
grep "/lib.*/libc.so.6 " dummy.log
echo Expected output: 'attempt to open /lib/libc.so.6 succeeded'
# Expected output:
# attempt to open /lib/libc.so.6 succeeded
grep found dummy.log
case $(uname -m) in
  x86_64)
    echo Expected output 'found ld-linux-x86-64.so.2 at /lib/ld-linux-x86-64.so.2'
  ;;
  aarch64)
    echo Expected output 'found ld-linux-aarch64.so.1 at /lib/ld-linux-aarch64.so.1'
  ;;
esac
# Cleanup
rm -v dummy.c a.out dummy.log
set -e
echo End sanity check - raw toolchain - adjusting the toolchain
touch /logs/status_adjusting_toolchain_complete

echo Zlib-1.2.12
tar xf zlib-1.2.12.tar.xz
pushd zlib-1.2.12
./configure --prefix=/usr
make -j$(nproc)
make install
popd
rm -rf zlib-1.2.12
touch /logs/status_zlib_complete

echo File-5.40
tar xf file-5.40.tar.gz
pushd file-5.40
./configure --prefix=/usr
make -j$(nproc)
make install
popd
rm -rf file-5.40
touch /logs/status_file_complete

echo Readline-8.1
tar xf readline-8.1.tar.gz
pushd readline-8.1
sed -i '/MV.*old/d' Makefile.in
sed -i '/{OLDSUFF}/c:' support/shlib-install
./configure --prefix=/usr    \
            --disable-static \
            --with-curses    \
            --docdir=/usr/share/doc/readline-8.1
make SHLIB_LIBS="-L/tools/lib -lncursesw"
make SHLIB_LIBS="-L/tools/lib -lncursesw" install
popd
rm -rf readline-8.1
touch /logs/status_readline_complete

echo M4-1.4.19
tar xf m4-1.4.19.tar.gz
pushd m4-1.4.19
./configure --prefix=/usr
make -j$(nproc)
make install
popd
rm -rf m4-1.4.19
touch /logs/status_m4_complete

echo Binutils-2.37
tar xf binutils-2.37.tar.xz
pushd binutils-2.37
patch -p1 -i /tools/linker-script-readonly-keyword-support.patch
sed -i '/@\tincremental_copy/d' gold/testsuite/Makefile.in
mkdir -v build
cd build
../configure --prefix=/usr       \
             --enable-gold       \
             --enable-ld=default \
             --enable-plugins    \
             --enable-shared     \
             --disable-werror    \
             --enable-64-bit-bfd \
             --with-system-zlib
#             --enable-install-libiberty
# libiberty.a used to be in binutils. Now it is in GCC.
make -j$(nproc) tooldir=/usr
make tooldir=/usr install
popd
rm -rf binutils-2.37
touch /logs/status_binutils_complete

echo GMP-6.2.1
tar xf gmp-6.2.1.tar.xz
pushd gmp-6.2.1
# Remove optimizations
cp -v configfsf.guess config.guess
cp -v configfsf.sub   config.sub
./configure --prefix=/usr    \
            --enable-cxx     \
            --disable-static \
            --docdir=/usr/share/doc/gmp-6.2.1 \
            --disable-assembly
make -j$(nproc)
make html
make install
make install-html
popd
rm -rf gmp-6.2.1
touch /logs/status_gmp_complete

echo MPFR-4.1.0
tar xf mpfr-4.1.0.tar.xz
pushd mpfr-4.1.0
./configure --prefix=/usr        \
            --disable-static     \
            --enable-thread-safe \
            --docdir=/usr/share/doc/mpfr-4.1.0
make -j$(nproc)
make html
make install
make install-html
popd
rm -rf mpfr-4.1.0
touch /logs/status_mpfr_complete

echo MPC-1.2.1
tar xf mpc-1.2.1.tar.gz
pushd mpc-1.2.1
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/mpc-1.2.1
make -j$(nproc)
make html
make install
make install-html
popd
rm -rf mpc-1.2.1
touch /logs/status_libmpc_complete

echo GCC-11.2.0
tar xf gcc-11.2.0.tar.xz
pushd gcc-11.2.0
# fix issue compiling with glibc 2.34
sed -e '/static.*SIGSTKSZ/d' \
    -e 's/return kAltStackSize/return SIGSTKSZ * 4/' \
    -i libsanitizer/sanitizer_common/sanitizer_posix_libcdep.cpp
case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
  ;;
  aarch64)
    sed -e '/mabi.lp64=/s/lib64/lib/' \
        -i.orig gcc/config/aarch64/t-aarch64-linux
  ;;
esac
# disable no-pie for gcc binaries
sed -i '/^NO_PIE_CFLAGS = /s/@NO_PIE_CFLAGS@//' gcc/Makefile.in
patch -Np1 -i /tools/CVE-2023-4039.patch
# LFS 7.4:  Workaround a bug so that GCC doesn't install libiberty.a, which is already provided by Binutils:
# sed -i 's/install_to_$(INSTALL_DEST) //' libiberty/Makefile.in
# Need to remove this link to /tools/lib/gcc as the final gcc includes will be installed here.
ls -la /usr/lib/gcc
ls /usr/lib/gcc
rm -f /usr/lib/gcc
mkdir -v build
cd       build
SED=sed \
../configure    --prefix=/usr \
                --enable-shared \
                --enable-threads=posix \
                --enable-__cxa_atexit \
                --enable-clocale=gnu \
                --enable-languages=c,c++\
                --disable-multilib \
                --disable-bootstrap \
                --enable-linker-build-id \
                --enable-plugin \
                --enable-default-pie \
                --with-system-zlib
# --enable-install-libiberty
# --disable-install-libiberty
make -j$(nproc)
make install
ln -sv ../usr/bin/cpp /lib
ln -sv gcc /usr/bin/cc

install -v -dm755 /usr/lib/bfd-plugins
ln -sfv ../../libexec/gcc/$(gcc -dumpmachine)/11.2.0/liblto_plugin.so /usr/lib/bfd-plugins/

# Sanity check
set +e
echo sanity check - raw toolchain - gcc 11.2.0
ldconfig -v
ldconfig -p
ldconfig
gcc -dumpmachine
sync
echo 'int main(){}' > dummy.c
cc dummy.c -v -Wl,--verbose &> dummy.log
cat dummy.log
readelf -l a.out
readelf -l a.out | grep ': /lib'
echo Expected output: '[Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]'
# Expected output:
# [Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]
grep -o '/usr/lib.*/crt[1in].*succeeded' dummy.log
# Expected output:
# /usr/lib/gcc/x86_64-pc-linux-gnu/11.2.0/../../../../lib/crt1.o succeeded
# /usr/lib/gcc/x86_64-pc-linux-gnu/11.2.0/../../../../lib/crti.o succeeded
# /usr/lib/gcc/x86_64-pc-linux-gnu/11.2.0/../../../../lib/crtn.o succeeded
grep -B4 '^ /usr/include' dummy.log
# Expected output:
# #include <...> search starts here:
#  /usr/lib/gcc/x86_64-pc-linux-gnu/11.2.0/include
#  /usr/local/include
#  /usr/lib/gcc/x86_64-pc-linux-gnu/11.2.0/include-fixed
#  /usr/include
grep 'SEARCH.*/usr/lib' dummy.log |sed 's|; |\n|g'
# Expected output:
# SEARCH_DIR("/usr/x86_64-pc-linux-gnu/lib64")
# SEARCH_DIR("/usr/local/lib64")
# SEARCH_DIR("/lib64")
# SEARCH_DIR("/usr/lib64")
# SEARCH_DIR("/usr/x86_64-pc-linux-gnu/lib")
# SEARCH_DIR("/usr/local/lib")
# SEARCH_DIR("/lib")
# SEARCH_DIR("/usr/lib");
grep "/lib.*/libc.so.6 " dummy.log
echo Expected output: 'attempt to open /lib/libc.so.6 succeeded'
# Expected output:
# attempt to open /lib/libc.so.6 succeeded
grep found dummy.log
echo Expected output: 'found ld-linux-x86-64.so.2 at /lib/ld-linux-x86-64.so.2'
# Expected output:
# found ld-linux-x86-64.so.2 at /lib/ld-linux-x86-64.so.2
rm -v dummy.c a.out dummy.log
echo End sanity check - raw toolchain - gcc 11.2.0
set -e

mkdir -pv /usr/share/gdb/auto-load/usr/lib
mv -v /usr/lib/*gdb.py /usr/share/gdb/auto-load/usr/lib
popd
rm -rf gcc-11.2.0

touch /logs/status_gcc_complete

echo Bzip2-1.0.8
tar xf bzip2-1.0.8.tar.gz
pushd bzip2-1.0.8
sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile
make -f Makefile-libbz2_so
make clean
make -j$(nproc)
make PREFIX=/usr install
cp -v bzip2-shared /bin/bzip2
cp -av libbz2.so* /lib
ln -sv ../../lib/libbz2.so.1.0 /usr/lib/libbz2.so
rm -v /usr/bin/{bunzip2,bzcat,bzip2}
ln -sv bzip2 /bin/bunzip2
ln -sv bzip2 /bin/bzcat
popd
rm -rf bzip2-1.0.8
touch /logs/status_bzip2_complete

echo Pkg-config-0.29.2
tar xf pkg-config-0.29.2.tar.gz
pushd pkg-config-0.29.2
./configure --prefix=/usr              \
            --with-internal-glib       \
            --disable-host-tool        \
            --docdir=/usr/share/doc/pkg-config-0.29.2
make -j$(nproc)
make install
popd
rm -rf pkg-config-0.29.2
touch /logs/status_pkgconfig_complete

echo Ncurses-6.2
tar xf ncurses-6.2.tar.gz
pushd ncurses-6.2
sed -i '/LIBTOOL_INSTALL/d' c++/Makefile.in
./configure --prefix=/usr           \
            --mandir=/usr/share/man \
            --with-shared           \
            --without-debug         \
            --without-normal        \
            --enable-pc-files       \
            --enable-widec
make -j$(nproc)
make install
#mv -v /usr/lib/libncursesw.so.6* /lib
#ln -sfv ../../lib/$(readlink /usr/lib/libncursesw.so) /usr/lib/libncursesw.so
for lib in ncurses form panel menu ; do
    rm -vf                    /usr/lib/lib${lib}.so
    echo "INPUT(-l${lib}w)" > /usr/lib/lib${lib}.so
    ln -sfv ${lib}w.pc        /usr/lib/pkgconfig/${lib}.pc
done
rm -vf                     /usr/lib/libcursesw.so
echo "INPUT(-lncursesw)" > /usr/lib/libcursesw.so
ln -sfv libncurses.so      /usr/lib/libcurses.so
# Documentation
mkdir -v       /usr/share/doc/ncurses-6.2
cp -v -R doc/* /usr/share/doc/ncurses-6.2
popd
rm -rf ncurses-6.2
touch /logs/status_ncurses_complete

echo libcap-2.60
tar xf libcap-2.60.tar.xz
pushd libcap-2.60
sed -i '/install.*STALIBNAME/d' libcap/Makefile
make -j$(nproc)
make RAISE_SETFCAP=no lib=lib prefix=/usr install
chmod -v 755 /usr/lib/libcap.so.2.60
#mv -v /usr/lib/libcap.so.* /lib
#ln -sfv ../../lib/$(readlink /usr/lib/libcap.so) /usr/lib/libcap.so
popd
rm -rf libcap-2.60
touch /logs/status_libcap_complete

echo Sed-4.8
tar xf sed-4.8.tar.xz
pushd sed-4.8
./configure --prefix=/usr --bindir=/bin
make -j$(nproc)
make install
popd
rm -rf sed-4.8
touch /logs/status_sed_complete

echo Bison-3.7.6
tar xf bison-3.7.6.tar.xz
pushd bison-3.7.6
./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.7.6
# Build with single processor due to errors seen with parallel make
#     cannot stat 'examples/c/reccalc/scan.stamp.tmp': No such file or directory
# try parallel make with new version
make -j$(nproc)
make install
popd
rm -rf bison-3.7.6
touch /logs/status_bison_complete

echo Flex-2.6.4
tar xf flex-2.6.4.tar.gz
pushd flex-2.6.4
sed -i "/math.h/a #include <malloc.h>" src/flexdef.h
HELP2MAN=/tools/bin/true \
./configure --prefix=/usr --docdir=/usr/share/doc/flex-2.6.4
make -j$(nproc)
make install
ln -sv flex /usr/bin/lex
popd
rm -rf flex-2.6.4
touch /logs/status_flex_complete

echo Grep-3.7
tar xf grep-3.7.tar.xz
pushd grep-3.7
./configure --prefix=/usr --bindir=/bin
make -j$(nproc)
make install
popd
rm -rf grep-3.7
touch /logs/status_grep_complete

echo Bash-5.1.8
tar xf bash-5.1.8.tar.gz
pushd bash-5.1.8
./configure --prefix=/usr                      \
            --docdir=/usr/share/doc/bash-5.1.8 \
            --without-bash-malloc              \
            --with-installed-readline
make -j$(nproc)
make install
cd /sources
rm -rf bash-5.1.8
touch /logs/status_bash_complete

echo Libtool-2.4.6
tar xf libtool-2.4.6.tar.xz
pushd libtool-2.4.6
./configure --prefix=/usr
make -j$(nproc)
make install
popd
rm -rf libtool-2.4.6
touch /logs/status_libtool_complete

echo GDBM-1.21
tar xf gdbm-1.21.tar.gz
pushd gdbm-1.21
./configure --prefix=/usr    \
            --disable-static \
            --enable-libgdbm-compat
make -j$(nproc)
make install
popd
rm -rf gdbm-1.21
touch /logs/status_gdbm_complete

echo gperf-3.1
tar xf gperf-3.1.tar.gz
pushd gperf-3.1
./configure --prefix=/usr --docdir=/usr/share/doc/gperf-3.1
make -j$(nproc)
make install
popd
rm -rf gperf-3.1
touch /logs/status_gperf_complete

echo Expat-2.4.8
tar xf expat-2.4.8.tar.bz2
pushd expat-2.4.8
sed -i 's|usr/bin/env |bin/|' run.sh.in
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/expat-2.4.8
make -j$(nproc)
make install
popd
rm -rf expat-2.4.8
touch /logs/status_expat_complete

echo Perl-5.32.0
tar xf perl-5.32.0.tar.xz
pushd perl-5.32.0
echo "127.0.0.1 localhost $(hostname)" > /etc/hosts
export BUILD_ZLIB=False
export BUILD_BZIP2=0
sh Configure -des -Dprefix=/usr                 \
                  -Dvendorprefix=/usr           \
                  -Dman1dir=/usr/share/man/man1 \
                  -Dman3dir=/usr/share/man/man3 \
                  -Dpager="/usr/bin/less -isR"  \
                  -Duseshrplib                  \
                  -Dusethreads
make -j$(nproc)
make install
unset BUILD_ZLIB BUILD_BZIP2
popd
rm -rf perl-5.32.0
touch /logs/status_perl_complete

echo Autoconf-2.71
tar xf autoconf-2.71.tar.xz
pushd autoconf-2.71
./configure --prefix=/usr
make -j$(nproc)
make install
popd
rm -rf autoconf-2.71
touch /logs/status_autoconf_complete

echo Automake-1.16.5
tar xf automake-1.16.5.tar.gz
pushd automake-1.16.5
./configure --prefix=/usr --docdir=/usr/share/doc/automake-1.16.5
make -j$(nproc)
make install
popd
rm -rf automake-1.16.5
touch /logs/status_automake_complete

echo Xz-5.2.5
tar xf xz-5.2.5.tar.xz
pushd xz-5.2.5
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/xz-5.2.5
make -j$(nproc)
make install
popd
rm -rf xz-5.2.5
touch /logs/status_xz_complete

echo zstd-1.5.0
tar xf zstd-1.5.0.tar.gz
pushd zstd-1.5.0
make -j$(nproc)
make install prefix=/usr pkgconfigdir=/usr/lib/pkgconfig
rm -v /usr/lib/libzstd.a
popd
rm -rf zstd-1.5.0
touch /logs/status_zstd_complete

echo Gettext-0.19.8.1
tar xf gettext-0.19.8.1.tar.xz
pushd gettext-0.19.8.1
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/gettext-0.19.8.1
make -j$(nproc)
make install
chmod -v 0755 /usr/lib/preloadable_libintl.so
popd
rm -rf gettext-0.19.8.1
touch /logs/status_gettext_complete

echo Elfutils-0.186
tar xjf elfutils-0.186.tar.bz2
pushd elfutils-0.186
./configure \
    --prefix=/usr \
    --disable-debuginfod \
    --enable-libdebuginfod=dummy
make -j$(nproc)
make -C libelf install
install -vm644 config/libelf.pc /usr/lib/pkgconfig
# Need to also install (libdw.so.1) to satisfy rpmbuild
make -C libdw install
# Need to install (eu-strip) as well
make install
popd
rm -rf elfutils-0.186
touch /logs/status_libelf_complete

echo Libffi-3.4.2
tar xf libffi-3.4.2.tar.gz
pushd libffi-3.4.2
# TODO: set generic build to avoid optimizations causing illegal operation errors on other processors
# options: https://gcc.gnu.org/onlinedocs/gcc-9.2.0/gcc/x86-Options.html
#          https://gcc.gnu.org/onlinedocs/gcc-9.2.0/gcc/AArch64-Options.html#AArch64-Options
# export CFLAGS
# export CXXFLAGS
# By default all package built using '-O2 -march=x86-64 -pipe' for CFLAGS and CXXFLAGS,
sed -e '/^includesdir/ s/$(libdir).*$/$(includedir)/' \
    -i include/Makefile.in
sed -e '/^includedir/ s/=.*$/=@includedir@/' \
    -e 's/^Cflags: -I${includedir}/Cflags:/' \
    -i libffi.pc.in
# Set GCC_ARCH
case $(uname -m) in
    x86_64)
        GCC_ARCH=x86-64
    ;;
    aarch64)
        GCC_ARCH=native
    ;;
esac
./configure \
    --prefix=/usr \
    --bindir=/bin \
    --libdir=/usr/lib \
    --disable-static \
    --with-gcc-arch=$GCC_ARCH
unset GCC_ARCH
#	CFLAGS="-O2 -g" \
#	CXXFLAGS="-O2 -g" \
# Libffi is causing error building: find: '/usr/src/mariner/BUILDROOT/libffi-3.4.2-1.cm1.x86_64//usr/lib64': No such file or directory
make -j$(nproc)
make install
popd
rm -rf libffi-3.4.2
touch /logs/status_libffi_complete

echo "Perl Test::Warnings"
tar xf Test-Warnings-0.028.tar.gz
pushd Test-Warnings-0.028
env PERL_MM_USE_DEFAULT=1 perl Makefile.PL INSTALLDIRS=vendor
make
make install
find . -name 'perllocal.pod' -delete
popd
rm -rf Test-Warnings-0.028
touch /logs/status_test_warnings_complete

echo "Perl Text::Template"
tar xf Text-Template-1.51.tar.gz
pushd Text-Template-1.51
env PERL_MM_USE_DEFAULT=1 perl Makefile.PL INSTALLDIRS=vendor
make
make install
find . -name 'perllocal.pod' -delete
popd
rm -rf Text-Template-1.51
touch /logs/status_text_template_complete

echo OpenSSL-1.1.1k
tar xf openssl-1.1.1k.tar.gz
pushd openssl-1.1.1k
sslarch=
./config --prefix=/usr \
         --openssldir=/etc/pki/tls \
         --libdir=lib \
         enable-ec_nistp_64_gcc_128 \
         shared \
         zlib-dynamic \
         ${sslarch} \
         no-mdc2 \
         no-sm2 \
         no-sm4 \
         '-DDEVRANDOM="\"/dev/urandom\""'
perl ./configdata.pm -d
make all -j$(nproc)
sed -i '/INSTALL_LIBS/s/libcrypto.a libssl.a//' Makefile
make MANSUFFIX=ssl install
popd
rm -rf openssl-1.1.1k
touch /logs/status_openssl_complete

echo Python-3.9.13
tar xf Python-3.9.13.tar.xz
pushd Python-3.9.13
./configure --prefix=/usr       \
            --with-platlibdir=lib \
            --enable-shared     \
            --with-system-expat \
            --with-system-ffi   \
            --with-ensurepip=yes
make -j$(nproc)
make install
chmod -v 755 /usr/lib/libpython3.9.so.1.0
chmod -v 755 /usr/lib/libpython3.so
ln -sfv pip3.9 /usr/bin/pip3
popd
rm -rf Python-3.9.13
touch /logs/status_python39_complete

echo Coreutils-8.32
tar xf coreutils-8.32.tar.xz
pushd coreutils-8.32
patch -Np1 -i ../coreutils-8.32-i18n-1.patch
case $(uname -m) in
    aarch64)
        patch -Np1 -i /tools/coreutils-fix-get-sys_getdents-aarch64.patch
    ;;
esac
autoreconf -fiv
FORCE_UNSAFE_CONFIGURE=1 ./configure \
            --prefix=/usr            \
            --enable-no-install-program=kill,uptime
make -j$(nproc)
make install
mv -v /usr/bin/chroot /usr/sbin
mv -v /usr/share/man/man1/chroot.1 /usr/share/man/man8/chroot.8
sed -i s/\"1\"/\"8\"/1 /usr/share/man/man8/chroot.8
popd
rm -rf coreutils-8.32
touch /logs/status_coreutils_complete

echo Diffutils-3.8
tar xf diffutils-3.8.tar.xz
pushd diffutils-3.8
./configure --prefix=/usr
make -j$(nproc)
make install
popd
rm -rf diffutils-3.8
touch /logs/status_diffutils_complete

echo Gawk-5.1.0
tar xf gawk-5.1.0.tar.xz
pushd gawk-5.1.0
sed -i 's/extras//' Makefile.in
./configure --prefix=/usr
make -j$(nproc)
make install
popd
rm -rf gawk-5.1.0
touch /logs/status_gawk_complete

echo Findutils-4.8.0
tar xf findutils-4.8.0.tar.xz
pushd findutils-4.8.0
./configure --prefix=/usr --localstatedir=/var/lib/locate
make -j$(nproc)
make install
#mv -v /usr/bin/find /bin
sed -i 's|find:=${BINDIR}|find:=/bin|' /usr/bin/updatedb
popd
rm -rf findutils-4.8.0
touch /logs/status_findutils_complete

echo Groff-1.22.3
tar xf groff-1.22.3.tar.gz
pushd groff-1.22.3
PAGE=letter ./configure --prefix=/usr
# Build with single processor due to errors seen with parallel make
make -j1
make install
popd
rm -rf groff-1.22.3
touch /logs/status_groff_complete

echo Gzip-1.11
tar xf gzip-1.11.tar.xz
pushd gzip-1.11
./configure --prefix=/usr
make -j$(nproc)
make install
#mv -v /usr/bin/gzip /bin
popd
rm -rf gzip-1.11
touch /logs/status_gzip_complete

echo Libpipeline-1.5.0
tar xf libpipeline-1.5.0.tar.gz
pushd libpipeline-1.5.0
./configure --prefix=/usr
make -j$(nproc)
make install
popd
rm -rf libpipeline-1.5.0
touch /logs/status_libpipeline_complete

echo Make-4.3
tar xf make-4.3.tar.gz
pushd make-4.3
./configure --prefix=/usr
make -j$(nproc)
make install
popd
rm -rf make-4.3
touch /logs/status_make_complete

echo Patch-2.7.6
tar xf patch-2.7.6.tar.xz
pushd patch-2.7.6
./configure --prefix=/usr
make -j$(nproc)
make install
popd
rm -rf patch-2.7.6
touch /logs/status_patch_complete

echo Man-DB-2.10.1
tar xf man-db-2.10.1.tar.xz
pushd man-db-2.10.1
./configure --prefix=/usr                        \
            --docdir=/usr/share/doc/man-db-2.10.1 \
            --sysconfdir=/etc                    \
            --disable-setuid                     \
            --with-browser=/usr/bin/lynx         \
            --with-systemdsystemunitdir=no       \
            --with-vgrind=/usr/bin/vgrind        \
            --with-grap=/usr/bin/grap
make -j$(nproc)
make install
popd
rm -rf man-db-2.10.1
touch /logs/status_man_db_complete

echo Tar-1.34
tar xf tar-1.34.tar.xz
pushd tar-1.34
FORCE_UNSAFE_CONFIGURE=1  \
./configure --prefix=/usr \
            --bindir=/bin
make -j$(nproc)
make install
popd
rm -rf tar-1.34
touch /logs/status_tar_complete

echo Texinfo-6.8
tar xf texinfo-6.8.tar.xz
pushd texinfo-6.8
./configure --prefix=/usr --disable-static
# fix issue building with glibc 2.34:
sed -e 's/__attribute_nonnull__/__nonnull/' \
    -i gnulib/lib/malloc/dynarray-skeleton.c
make -j$(nproc)
make install
make TEXMF=/usr/share/texmf install-tex
popd
rm -rf texinfo-6.8
touch /logs/status_texinfo_complete

echo Procps-ng-3.3.17
tar xf procps-ng-3.3.17.tar.xz
pushd procps-3.3.17
./configure --prefix=/usr                            \
            --exec-prefix=                           \
            --libdir=/usr/lib                        \
            --docdir=/usr/share/doc/procps-ng-3.3.17 \
            --disable-static                         \
            --disable-kill
make -j$(nproc)
make install
#mv -v /usr/lib/libprocps.so.* /lib
#ln -sfv ../../lib/$(readlink /usr/lib/libprocps.so) /usr/lib/libprocps.so
popd
rm -rf procps-3.3.17
touch /logs/status_procpsng_complete

echo util-linux-2.37.4
tar xf util-linux-2.37.4.tar.xz
pushd util-linux-2.37.4
mkdir -pv /var/lib/hwclock
./configure ADJTIME_PATH=/var/lib/hwclock/adjtime   \
            --docdir=/usr/share/doc/util-linux-2.37.4 \
            --disable-chfn-chsh  \
            --disable-login      \
            --disable-nologin    \
            --disable-su         \
            --disable-setpriv    \
            --disable-runuser    \
            --disable-pylibmount \
            --disable-static     \
            --without-python     \
            --without-systemd    \
            --without-systemdsystemunitdir
make -j$(nproc)
make install
popd
rm -rf util-linux-2.37.4
touch /logs/status_util-linux_complete

#
# These next packages include rpm/rpmbuild and dependencies
#
echo Building RPM related packages
cd /sources

echo sqlite-autoconf-3360000
tar xf sqlite-autoconf-3360000.tar.gz
pushd sqlite-autoconf-3360000
./configure --prefix=/usr     \
        --disable-static  \
        --enable-fts5     \
        CFLAGS="-g -O2                    \
        -DSQLITE_ENABLE_FTS3=1            \
        -DSQLITE_ENABLE_FTS4=1            \
        -DSQLITE_ENABLE_COLUMN_METADATA=1 \
        -DSQLITE_ENABLE_UNLOCK_NOTIFY=1   \
        -DSQLITE_ENABLE_DBSTAT_VTAB=1     \
        -DSQLITE_SECURE_DELETE=1          \
        -DSQLITE_ENABLE_FTS3_TOKENIZER=1"
make -j$(nproc)
make install
popd
rm -rf sqlite-autoconf-3360000
touch /logs/status_sqlite-autoconf_complete

echo popt-1.18
tar xf popt-1.18.tar.gz
pushd popt-1.18
./configure --prefix=/usr \
        --disable-static \
        --build=$BUILD_TARGET
make -j$(nproc)
make install
popd
rm -rf popt-1.18
touch /logs/status_popt_complete

echo cpio-2.13
tar xjf cpio-2.13.tar.bz2
pushd cpio-2.13
patch -Np1 -i /tools/cpio_extern_nocommon.patch
patch -Np1 -i /tools/CVE-2021-38185.patch
./configure --prefix=/usr \
        --bindir=/bin \
        --enable-mt   \
        --with-rmt=/usr/libexec/rmt \
        --build=$BUILD_TARGET
make -j$(nproc)
makeinfo --html            -o doc/html      doc/cpio.texi
makeinfo --html --no-split -o doc/cpio.html doc/cpio.texi
makeinfo --plaintext       -o doc/cpio.txt  doc/cpio.texi
make install
install -v -m755 -d /usr/share/doc/cpio-2.13/html
install -v -m644    doc/html/* \
                /usr/share/doc/cpio-2.13/html
install -v -m644    doc/cpio.{html,txt} \
                /usr/share/doc/cpio-2.13
popd
rm -rf cpio-2.13
touch /logs/status_cpio_complete

echo libarchive-3.6.1
tar xf libarchive-3.6.1.tar.gz
pushd libarchive-3.6.1
./configure --prefix=/usr --disable-static
make -j$(nproc)
make install
popd
rm -rf libarchive-3.6.1
touch /logs/status_libarchive_complete

echo lua-5.4.4
tar xf lua-5.4.4.tar.gz
pushd lua-5.4.4
cat > lua.pc << "EOF"
V=5.4
R=5.4.4
prefix=/usr
INSTALL_BIN=${prefix}/bin
INSTALL_INC=${prefix}/include
INSTALL_LIB=${prefix}/lib
INSTALL_MAN=${prefix}/share/man/man1
INSTALL_LMOD=${prefix}/share/lua/${V}
INSTALL_CMOD=${prefix}/lib/lua/${V}
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include
Name: Lua
Description: An Extensible Extension Language
Version: ${R}
Requires:
Libs: -L${libdir} -llua -lm -ldl
Cflags: -I${includedir}
EOF
patch -Np1 -i ../lua-5.4.4-shared_library-2.patch
sed -i '/#define LUA_ROOT/s:/usr/local/:/usr/:' src/luaconf.h
make MYCFLAGS="-DLUA_COMPAT_5_2 -DLUA_COMPAT_5_1" linux
make INSTALL_TOP=/usr                \
     INSTALL_DATA="cp -d"            \
     INSTALL_MAN=/usr/share/man/man1 \
     TO_LIB="liblua.so liblua.so.5.4 liblua.so.5.4.4" \
     install
mkdir -pv                      /usr/share/doc/lua-5.4.4
cp -v doc/*.{html,css,gif,png} /usr/share/doc/lua-5.4.4
install -v -m644 -D lua.pc /usr/lib/pkgconfig/lua.pc
popd
rm -rf lua-5.4.4
touch /logs/status_lua_complete

DEBUGEDIT_WITH_VERSION=debugedit-5.0
echo $DEBUGEDIT_WITH_VERSION
tar xf "$DEBUGEDIT_WITH_VERSION".tar.xz
pushd "$DEBUGEDIT_WITH_VERSION"
./configure --prefix=/usr
make
make install
popd
rm -rf "$DEBUGEDIT_WITH_VERSION"
touch /logs/status_debugedit_complete

RPM_WITH_VERSION=rpm-4.17.0
RPM_FOLDER="$RPM_WITH_VERSION"-release
echo $RPM_WITH_VERSION
tar xf "$RPM_WITH_VERSION"-release.tar.gz
mv rpm-"$RPM_WITH_VERSION"-release "$RPM_FOLDER"
pushd "$RPM_FOLDER"

# Still not in the upstream
patch -Np1 -i /tools/rpm-define-RPM-LD-FLAGS.patch

# Do not build docs - pandoc dependency is not supplied in the toolchain.
sed -iE '/SUBDIRS/ s/docs //' Makefile.am
sed -iE '/Always build/,+16 d' Makefile.am

./autogen.sh --noconfigure
./configure --prefix=/usr \
        --enable-ndb \
        --without-selinux \
        --with-crypto=openssl \
        --with-vendor=mariner

make -j$(nproc)
make install
install -d /var/lib/rpm

rpm --initdb --root=/ --dbpath /var/lib/rpm
popd

rm -rf "$RPM_FOLDER"

# Fix the interpreter path for python replacing the first line
sed -i '1 s:.*:#!/usr/bin/python3:' pythondistdeps.py
install -p pythondistdeps.py /usr/lib/rpm/pythondistdeps.py
install -p pythondeps.sh /usr/lib/rpm/pythondeps.sh
install -p python.attr /usr/lib/rpm/fileattrs/python.attr

touch /logs/status_rpm_complete

# Cleanup
rm -rf /tmp/*

echo sanity check - raw toolchain - after build complete - gcc -v
gcc -v

touch /logs/status_building_in_chroot_complete
