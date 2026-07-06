# Native Windows VPN roadmap

OrexRay 0.4.0 intentionally uses three practical modes: System Proxy, VPN/TUN and Local Proxy.

A future Windows-native integration is possible through the Windows VPN platform and a custom VPN plug-in. That is different from wrapping Xray's TUN traffic inside PPTP/L2TP/IKEv2/SSTP. A built-in protocol wrapper would require implementing a real compatible VPN endpoint and bridge, while a custom VPN plug-in lets Windows own the VPN connection lifecycle.

This is a later milestone because it requires a separate Windows-native component, packaged deployment and VPN-provider capability work. It should not block a stable Xray client today.
