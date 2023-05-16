Vendor:         Microsoft Corporation
Distribution:   Mariner
# generated by cabal-rpm-2.0.9
# https://docs.fedoraproject.org/en-US/packaging-guidelines/Haskell/

%global pkg_name safe
%global pkgver %{pkg_name}-%{version}

# disable temporarily to build with just ghc
%bcond_with tests

Name:           ghc-%{pkg_name}
Version:        0.3.19
Release:        9%{?dist}
Summary:        Library of safe (exception free) functions

License:        BSD
Url:            https://hackage.haskell.org/package/%{pkg_name}
# Begin cabal-rpm sources:
Source0:        https://hackage.haskell.org/package/%{pkgver}/%{pkgver}.tar.gz
# End cabal-rpm sources

# Begin cabal-rpm deps:
BuildRequires:  ghc-Cabal-devel
BuildRequires:  ghc-rpm-macros
BuildRequires:  ghc-base-prof
%if %{with tests}
BuildRequires:  ghc-QuickCheck-devel
BuildRequires:  ghc-deepseq-devel
%endif
# End cabal-rpm deps

%description
A library wrapping 'Prelude'/'Data.List' functions that can throw exceptions,
such as 'head' and '!!'. Each unsafe function has up to four variants, e.g.
with 'tail':

* 'tail :: [a] -> [a]', raises an error on 'tail []'.

* 'tailMay :: [a] -> /Maybe/ [a]', turns errors into 'Nothing'.

* 'tailDef :: /[a]/ -> [a] -> [a]', takes a default to return on errors.

* 'tailNote :: /String/ -> [a] -> [a]', takes an extra argument which
supplements the error message.

* 'tailSafe :: [a] -> [a]', returns some sensible default if possible, '[]' in
the case of 'tail'.

This package is divided into three modules:

* "Safe" contains safe variants of 'Prelude' and 'Data.List' functions.

* "Safe.Foldable" contains safe variants of 'Foldable' functions.

* "Safe.Exact" creates crashing versions of functions like 'zip' (errors if the
lists are not equal) and 'take' (errors if there are not enough elements), then
wraps them to provide safe variants.


%package devel
Summary:        Haskell %{pkg_name} library development files
Provides:       %{name}-static = %{version}-%{release}
Provides:       %{name}-static%{?_isa} = %{version}-%{release}
%if %{defined ghc_version}
Requires:       ghc-compiler = %{ghc_version}
%endif
Requires:       %{name}%{?_isa} = %{version}-%{release}

%description devel
This package provides the Haskell %{pkg_name} library development files.


%if %{with haddock}
%package doc
Summary:        Haskell %{pkg_name} library documentation
BuildArch:      noarch
Requires:       ghc-filesystem

%description doc
This package provides the Haskell %{pkg_name} library documentation.
%endif


%if %{with ghc_prof}
%package prof
Summary:        Haskell %{pkg_name} profiling library
Requires:       %{name}-devel%{?_isa} = %{version}-%{release}
Supplements:    (%{name}-devel and ghc-prof)

%description prof
This package provides the Haskell %{pkg_name} profiling library.
%endif


%prep
# Begin cabal-rpm setup:
%setup -q -n %{pkgver}
# End cabal-rpm setup


%build
# Begin cabal-rpm build:
%ghc_lib_build
# End cabal-rpm build


%install
# Begin cabal-rpm install
%ghc_lib_install
# End cabal-rpm install


%check
%if %{with tests}
%cabal_test
%endif


%files -f %{name}.files
# Begin cabal-rpm files:
%license LICENSE
# End cabal-rpm files


%files devel -f %{name}-devel.files
%doc CHANGES.txt README.md


%if %{with haddock}
%files doc -f %{name}-doc.files
%license LICENSE
%endif


%if %{with ghc_prof}
%files prof -f %{name}-prof.files
%endif


%changelog
* Thu Jul 21 2022 Fedora Release Engineering <releng@fedoraproject.org> - 0.3.19-9
- Rebuilt for https://fedoraproject.org/wiki/Fedora_37_Mass_Rebuild

* Fri Jun 17 2022 Jens Petersen <petersen@redhat.com> - 0.3.19-8
- rebuild

* Thu Jan 20 2022 Fedora Release Engineering <releng@fedoraproject.org> - 0.3.19-7
- Rebuilt for https://fedoraproject.org/wiki/Fedora_36_Mass_Rebuild

* Fri Aug 06 2021 Jens Petersen <petersen@redhat.com> - 0.3.19-6
- rebuild

* Thu Jul 22 2021 Fedora Release Engineering <releng@fedoraproject.org> - 0.3.19-5
- Rebuilt for https://fedoraproject.org/wiki/Fedora_35_Mass_Rebuild

* Tue Jan 26 2021 Fedora Release Engineering <releng@fedoraproject.org> - 0.3.19-4
- Rebuilt for https://fedoraproject.org/wiki/Fedora_34_Mass_Rebuild

* Sat Aug 01 2020 Fedora Release Engineering <releng@fedoraproject.org> - 0.3.19-3
- Second attempt - Rebuilt for
  https://fedoraproject.org/wiki/Fedora_33_Mass_Rebuild

* Mon Jul 27 2020 Fedora Release Engineering <releng@fedoraproject.org> - 0.3.19-2
- Rebuilt for https://fedoraproject.org/wiki/Fedora_33_Mass_Rebuild

* Wed Jun 10 2020 Jens Petersen <petersen@redhat.com> - 0.3.19-1
- update to 0.3.19

* Fri Feb 14 2020 Jens Petersen <petersen@redhat.com> - 0.3.18-1
- update to 0.3.18

* Tue Jan 28 2020 Fedora Release Engineering <releng@fedoraproject.org> - 0.3.17-6
- Rebuilt for https://fedoraproject.org/wiki/Fedora_32_Mass_Rebuild

* Fri Aug 02 2019 Jens Petersen <petersen@redhat.com> - 0.3.17-5
- add doc and prof subpackages (cabal-rpm-1.0.0)

* Thu Jul 25 2019 Fedora Release Engineering <releng@fedoraproject.org> - 0.3.17-4
- Rebuilt for https://fedoraproject.org/wiki/Fedora_31_Mass_Rebuild

* Sun Feb 17 2019 Jens Petersen <petersen@redhat.com> - 0.3.17-3
- refresh to cabal-rpm-0.13

* Thu Jan 31 2019 Fedora Release Engineering <releng@fedoraproject.org> - 0.3.17-2
- Rebuilt for https://fedoraproject.org/wiki/Fedora_30_Mass_Rebuild

* Sun Jul 22 2018 Jens Petersen <petersen@redhat.com> - 0.3.17-1
- update to 0.3.17

* Fri Jul 13 2018 Fedora Release Engineering <releng@fedoraproject.org> - 0.3.15-3
- Rebuilt for https://fedoraproject.org/wiki/Fedora_29_Mass_Rebuild

* Wed Feb 07 2018 Fedora Release Engineering <releng@fedoraproject.org> - 0.3.15-2
- Rebuilt for https://fedoraproject.org/wiki/Fedora_28_Mass_Rebuild

* Wed Jan 24 2018 Jens Petersen <petersen@redhat.com> - 0.3.15-1
- update to 0.3.15

* Wed Aug 02 2017 Fedora Release Engineering <releng@fedoraproject.org> - 0.3.14-3
- Rebuilt for https://fedoraproject.org/wiki/Fedora_27_Binutils_Mass_Rebuild

* Wed Jul 26 2017 Fedora Release Engineering <releng@fedoraproject.org> - 0.3.14-2
- Rebuilt for https://fedoraproject.org/wiki/Fedora_27_Mass_Rebuild

* Thu Feb 23 2017 Jens Petersen <petersen@redhat.com> - 0.3.14-1
- update to 0.3.14

* Fri Feb 10 2017 Fedora Release Engineering <releng@fedoraproject.org> - 0.3.9-3
- Rebuilt for https://fedoraproject.org/wiki/Fedora_26_Mass_Rebuild

* Wed Feb 03 2016 Fedora Release Engineering <releng@fedoraproject.org> - 0.3.9-2
- Rebuilt for https://fedoraproject.org/wiki/Fedora_24_Mass_Rebuild

* Sat Aug 08 2015 Ben Boeckel <mathstuf@gmail.com> - 0.3.9-1
- update to 0.3.9

* Wed Jun 17 2015 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.3.8-2
- Rebuilt for https://fedoraproject.org/wiki/Fedora_23_Mass_Rebuild

* Tue Jan 20 2015 Jens Petersen <petersen@redhat.com> - 0.3.8-1
- update to 0.3.8

* Sat Aug 16 2014 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.3.3-10
- Rebuilt for https://fedoraproject.org/wiki/Fedora_21_22_Mass_Rebuild

* Sat Jun 07 2014 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.3.3-9
- Rebuilt for https://fedoraproject.org/wiki/Fedora_21_Mass_Rebuild

* Sat Aug 03 2013 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.3.3-8
- Rebuilt for https://fedoraproject.org/wiki/Fedora_20_Mass_Rebuild

* Wed Jun 05 2013 Jens Petersen <petersen@redhat.com> - 0.3.3-7
- update to new simplified Haskell Packaging Guidelines

* Wed Feb 13 2013 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.3.3-6
- Rebuilt for https://fedoraproject.org/wiki/Fedora_19_Mass_Rebuild

* Sat Nov 17 2012 Jens Petersen <petersen@redhat.com> - 0.3.3-5
- update with cabal-rpm

* Thu Jul 19 2012 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.3.3-4
- Rebuilt for https://fedoraproject.org/wiki/Fedora_18_Mass_Rebuild

* Mon Jul 16 2012 Jens Petersen <petersen@redhat.com> - 0.3.3-3
- change prof BRs to devel

* Fri Mar 23 2012 Jens Petersen <petersen@redhat.com> - 0.3.3-2
- add license to ghc_files

* Fri Jan  6 2012 Jens Petersen <petersen@redhat.com> - 0.3.3-1
- update to 0.3.3 and cabal2spec-0.25.2

* Fri Oct 21 2011 Marcela Mašláňová <mmaslano@redhat.com> - 0.3-5.2
- rebuild with new gmp without compat lib

* Tue Oct 11 2011 Peter Schiffer <pschiffe@redhat.com> - 0.3-5.1
- rebuild with new gmp

* Sat Jul 09 2011 Ben Boeckel <mathstuf@gmail.com> - 0.3-5
- Update to cabal2spec-0.24

* Fri Jun 24 2011 Jens Petersen <petersen@redhat.com> - 0.3-4
- BR ghc-Cabal-devel instead of ghc-prof and use ghc_arches (cabal2spec-0.23.2)

* Thu Mar 10 2011 Fabio M. Di Nitto <fdinitto@redhat.com> - 0.3-3
- Enable build on sparcv9

* Tue Feb 08 2011 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.3-2
- Rebuilt for https://fedoraproject.org/wiki/Fedora_15_Mass_Rebuild

* Sat Jan 15 2011 Ben Boeckel <mathstuf@gmail.com> - 0.3-1
- Update to 0.3

* Fri Sep 03 2010 Ben Boeckel <mathstuf@gmail.com> - 0.2-1
- Initial package

* Fri Sep  3 2010 Fedora Haskell SIG <haskell-devel@lists.fedoraproject.org> - 0.2-0
- initial packaging for Fedora automatically generated by cabal2spec-0.22.2