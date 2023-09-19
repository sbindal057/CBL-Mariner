Summary:        Grub2 Macros for AzureLinux
Name:           grub2-rpm-macros
Version:        1
Release:        1%{?dist}
License:        GPLv3+
Vendor:         Microsoft Corporation
Distribution:   Mariner
Group:          Development/Tools
Source0:        macros.grub2
BuildArch:      noarch

%description
This package contains grub2 RPM macros.
Needed for RPMS which depend on AzureLinux-specific macro
behavior for modifying the grub boot behavior. 

%prep
%autosetup -c -T
cp -a %{sources} .

%install
mkdir -p %{buildroot}%{_rpmconfigdir}/macros.d
install -pm 644 macros.* %{buildroot}/%{_rpmconfigdir}/macros.d

%files
%{_rpmconfigdir}/macros.d/macros.grub2

%changelog
* Mon Sep 18 2023 Cameron Baird <cameronbaird@microsoft.com> - 1-1
- Initial package
- Contains macros for supporting packages that modify boot behavior
    on systems using grub2-mkconfig to generate the boot configuration.