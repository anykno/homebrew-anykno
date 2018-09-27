class Gdb < Formula
  desc "GNU debugger"
  homepage "https://www.gnu.org/software/gdb/"
  url "https://ftp.gnu.org/gnu/gdb/gdb-8.2.tar.xz"
  mirror "https://ftpmirror.gnu.org/gdb/gdb-8.2.tar.xz"
  sha256 "c3a441a29c7c89720b734e5a9c6289c0a06be7e0c76ef538f7bbcef389347c39"

  option "with-python", "Use the Homebrew version of Python; by default system Python is used"
  option "with-python@2", "Use the Homebrew version of Python 2; by default system Python is used"
  option "with-version-suffix", "Add a version suffix to program"
  option "with-all-targets", "Build with support for all targets"

  deprecated_option "with-brewed-python" => "with-python@2"
  deprecated_option "with-guile" => "with-guile@2.0"

  depends_on "pkg-config" => :build
  depends_on "guile@2.0" => :optional
  depends_on "python" => :optional
  depends_on "python@2" => :optional

  fails_with :clang do
    build 800
    cause <<~EOS
      probe.c:63:28: error: default initialization of an object of const type
      'const any_static_probe_ops' without a user-provided default constructor
    EOS
  end

  fails_with :clang do
    build 600
    cause <<~EOS
      clang: error: unable to execute command: Segmentation fault: 11
      Test done on: Apple LLVM version 6.0 (clang-600.0.56) (based on LLVM 3.5svn)
    EOS
  end

  def install
    args = [
      "--prefix=#{prefix}",
      "--disable-debug",
      "--disable-dependency-tracking",
    ]

    args << "--with-guile" if build.with? "guile@2.0"
    args << "--enable-targets=all" if build.with? "all-targets"

    if build.with?("python@2") && build.with?("python")
      odie "Options --with-python and --with-python@2 are mutually exclusive."
    elsif build.with?("python@2")
      args << "--with-python=#{Formula["python@2"].opt_bin}/python2"
      ENV.append "CPPFLAGS", "-I#{Formula["python@2"].opt_libexec}"
    elsif build.with?("python")
      args << "--with-python=#{Formula["python"].opt_bin}/python3"
      ENV.append "CPPFLAGS", "-I#{Formula["python"].opt_libexec}"
    else
      args << "--with-python=/usr"
    end

    if build.with? "version-suffix"
      args << "--program-suffix=-#{version.to_s.slice(/^\d/)}"
    end

    system "./configure", *args
    system "make"

    # Don't install bfd or opcodes, as they are provided by binutils
    inreplace ["bfd/Makefile", "opcodes/Makefile"], /^install:/, "dontinstall:"

    system "make", "install"
  end

  def caveats; <<~EOS
    gdb requires special privileges to access Mach ports.
    You will need to codesign the binary. For instructions, see:

      https://sourceware.org/gdb/wiki/BuildingOnDarwin

    On 10.12 (Sierra) or later with SIP, you need to run this:

      echo "set startup-with-shell off" >> ~/.gdbinit
  EOS
  end

  patch :p0, :DATA

  test do
    system bin/"gdb", bin/"gdb", "-configuration"
  end
end

__END__
--- gdb/remote.c	2018-09-27 17:16:06.000000000 +0800
+++ gdb/remote.c	2018-09-27 17:15:27.000000000 +0800
@@ -8035,8 +8035,17 @@ remote_target::process_g_packet (struct 
 
   /* Further sanity checks, with knowledge of the architecture.  */
   if (buf_len > 2 * rsa->sizeof_g_packet)
-    error (_("Remote 'g' packet reply is too long (expected %ld bytes, got %d "
-	     "bytes): %s"), rsa->sizeof_g_packet, buf_len / 2, rs->buf);
+  {
+    rsa->sizeof_g_packet = buf_len;
+    for (i = 0; i < gdbarch_num_regs(gdbarch); i++) {
+      if (rsa->regs[i].pnum == -1)
+        continue;
+      if (rsa->regs[i].offset >= rsa->sizeof_g_packet)
+        rsa->regs[i].in_g_packet = 0;
+      else
+        rsa->regs[i].in_g_packet = 1;
+    }
+  }
 
   /* Save the size of the packet sent to us by the target.  It is used
      as a heuristic when determining the max size of packets that the
