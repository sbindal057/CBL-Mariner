Summary:        Metapackage with kata virtualization packages
Name:           kata-packages
Version:        1.0
Release:        1%{?dist}
License:        ASL 2.0
Vendor:         Microsoft Corporation
Distribution:   Mariner
Group:          System Environment/Base
URL:            https://aka.ms/mariner

%description
Metapackage holding sets of kata virtualization packages

%package        kata
Summary:        Metapackage holding sets of kata virtualization packages
Requires:       kernel-mshv
Requires:       hvloader
Requires:       mshv-bootloader-lx
Requires:       mshv
Requires:       cloud-hypervisor
Requires:       cloud-hypervisor-cvm
Requires:       moby-containerd-cc
Requires:       kata-containers
Requires:       kata-containers-cc
Requires:       kernel-uvm
Requires:       kernel-uvm-cvm
Requires:       kernel-uvm-devel

%description    kata
%{summary}

%prep

%build

%files kata

%changelog
* Wed Aug 16 2023 Mitch Zhu <mitchzhu@microsoft.com> - 1.0-1
- Initial kata meta package