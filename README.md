# 🚀 Xray Auto Deployment Script (VLESS+Reality-Vision/xhttp)

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![System](https://img.shields.io/badge/System-Debian%20%7C%20Ubuntu-orange)](https://github.com/ISFZY/Xray-Auto)

[中文文档](#chinese) | [English Description](#english)

---

<a name="chinese"></a>
## 🇨🇳 中文说明
这是一个全自动化的 Xray 部署脚本，基于 **VLESS + Reality-Vision/(xhttp)** 顶尖流控协议。专为 Debian 和 Ubuntu 系统设计，提供极致的性能优化与安全防护。

* 版本: v0.3
* 核心: VLESS + Reality (Vision / xhttp)
* 系统: Debian / Ubuntu
 
### ✨ 核心功能

* **⚡️ 极速协议**: 部署最新的 VLESS + Reality-Vision/xhttp 流控组合。
* **🧠 智能 SNI 优选**: 自动测试并选择延迟最低的大厂域名（Apple, Microsoft 等）作为伪装目标，拒绝卡顿。
* **🛡️ 独家防火墙策略**: 采用 **白名单模式** (Whitelist)，默认拒绝所有非必要端口，隐藏服务器指纹。
* **🔄 一键回国模式切换与信息回显**: 独有的 `mode` 指令，支持一键切换 **阻断回国 (Block CN)** 或 **允许回国 (Allow CN)** 流量。`info` 指令：回显配置、VLESS, 二维码信息。
* **⚙️ 系统深度优化**: 
    * 自动开启 BBR + FQ 加速。
    * 智能 Swap 管理（内存 < 2G 时自动创建 1G Swap）。
    * 集成 Fail2ban 防暴力破解，自动适配 SSH 端口。
* **🤖 全自动静默安装**: 完美解决 Ubuntu/Debian 安装过程中的各种弹窗询问，实现真正的无人值守部署。

### 🛑 安装前必读：风险审计与注意事项
>**[!WARNING]**
> 警告：本脚本包含强制性的系统修改操作，请务必在运行前阅读以下风险清单。
> 强烈建议仅在全新的、纯净的 VPS 系统上运行此脚本。
>
**1. 🔥 网络与防火墙风险 (严重)**

| 风险点 | 详细描述 | 后果 |
|---|---|---|
| 暴力重置防火墙 | 脚本会执行 iptables -F 清空所有规则。 | 如果你的服务器上有 Docker、K8s 或自定义的路由转发，网络将立即瘫痪。 |
| 默认拒绝策略 | 仅放行 SSH、443、8443 端口，其余入站流量全部 DROP。 | 如果你修改了 SSH 端口且脚本未检测到，或者使用 VNC/Web面板，你将被锁在服务器外。 |
| 流量限制（BT） | 脚本内置路由规则，强制阻断 BitTorrent 协议。 | 无法使用此节点进行 BT/P2P 下载。（防止 DMCA 投诉导致 VPS 被商家封锁）。 |

**2. ⚙️ 系统环境风险 (中等)**
 * 强制杀进程：脚本运行初期会执行 killall apt，如果后台正在进行系统更新，可能导致 dpkg 数据库损坏。
 * 强制内核/系统升级：脚本包含 apt-get upgrade，可能会升级内核。对特定内核版本有依赖的环境请勿运行。
 * Swap 创建：会在磁盘强制创建 1GB Swap 文件（如果内存<2G）。

**3. 📱 客户端兼容性 (重要)**
(本脚本部署了两种最新协议，请确保你的客户端支持)：
 * 节点 1 (Vision): 需要 Xray-core v1.8.0+ (如 v2rayN 6.x+, Shadowrocket 最新版)。
 * 节点 2 (xhttp): 极新协议 (Xray v1.8.24+)，目前仅少数最新版客户端（如 v2rayN 预发行版、Shadowrocket、Nekobox 最新版）支持。

### 🛠️ 安装指南
环境要求:
 * 系统: Debian 10+ / Ubuntu 20.04+
 * 权限: Root 用户

**🚀 快速安装**
```
bash <(curl -Ls https://github.com/ISFZY/Xray-Auto/raw/main/install.sh)

```
**🗑️ 卸载**
如果你想移除 Xray 及其相关配置：
```
bash <(curl -sL https://github.com/ISFZY/Xray-Auto/raw/main/remove.sh)

```
### 常用指令
| 指令 | 说明 |
| ---- | ---- |
| `mode` | 查看当前分流策略状态（阻断/允许回国） |
| `info` | 信息回显：包含节点配置信息、VLESS链接，二维码 |
### 📝 配置说明
安装结束后，脚本会自动输出连接信息，包含：
* 节点配置信息：ip、端口、SNI等，用于手输时使用。
* VLESS 链接：可直接复制导入客户端（如 v2rayN, V2Box, Shadowrocket 等）。
* 二维码：手机扫码直连。


### ⚠️ 免责声明 | Disclaimer
本项目（脚本及相关文档）依据 [**GNU General Public License v3.0 (GPL-3.0)**](https://github.com/ISFZY/Xray-Auto/blob/main/LICENSE) 许可证开源。在使用本项目之前，请务必仔细阅读以下条款。一旦您下载、安装或使用本项目，即表示您已阅读并同意本免责声明的全部内容。

### 1. 软件及其衍生品仅仅用于技术研究
本项目及其包含的脚本（`install.sh`）仅供网络安全技术研究、服务器性能测试及计算机网络教学之用。
- 开发者**不鼓励、不支持也不协助**任何违反当地法律法规的行为。
- 用户在使用本项目时，必须严格遵守服务器所在地及用户所在地的所有法律法规。

### 2. "AS IS" (按原样) 条款与无担保声明
根据 GPL-3.0 协议第 15 和 16 条款：
- 本项目**按“原样”提供**，不提供任何明示或暗示的保证，包括但不限于对适销性、特定用途适用性和非侵权性的保证。
- 开发者不对因使用本脚本而导致的任何直接、间接、偶然、特殊或后果性的损害（包括但不限于数据丢失、业务中断、服务器被封锁或系统崩溃）承担任何责任。

### 3. 系统修改与风险提示
- 本脚本在运行时需要 root 权限，并会对系统进行深层修改，包括但不限于：
- 修改系统时区与内核参数（开启 BBR、配置虚拟内存 Swap）。
- 安装第三方依赖软件包与系统服务。
- 修改防火墙规则与 SSH 服务配置。
**用户需自行承担运行脚本可能带来的系统不稳定性或配置冲突风险。** 建议在纯净的系统环境下运行，并在操作前做好数据备份。

### 4. 第三方服务与网络内容
- 本脚本会从第三方源（如 GitHub、Loyalsoldier 等）下载核心组件和规则文件。开发者无法保证这些第三方服务的持续可用性或内容的安全性。
- 本脚本仅作为网络通讯工具，不提供任何具体的网络服务。开发者不对用户通过本工具传输、访问的任何内容的合法性、真实性或安全性负责。

### 5. 滥用后果
若用户将本项目用于非法用途（包括但不限于规避网络审查、进行网络攻击、传播违法信息等），由此产生的一切法律后果与责任均由用户自行承担，与本项目开发者无关。

---
*如果您不同意上述任何条款，请立即停止下载、安装或使用本项目。*


---

<a name="English"></a>
## 🇺🇸 English Description
An advanced, fully automated deployment script for Xray, featuring VLESS + Reality-Vision. Designed for performance, security, and ease of use on Debian and Ubuntu systems.

* Version: v0.3
* Core: VLESS + Reality (Vision / xhttp)
* OS: : Debian / Ubuntu

### ✨ Key Features
 * ⚡️ Cutting-edge Protocol: Deploys VLESS + Reality-Vision/xhttp flow control.
 * 🧠 Intelligent SNI Selection: Automatically pings and selects the fastest domain (e.g., Apple, Microsoft) for camouflage to ensure stability.
 * 🛡️ Advanced Security: Uses iptables Whitelist Mode by default, blocking all unauthorized ports to hide server fingerprint.
 * 🔄 One-Key Routing Switch: Exclusive 'mode' command to toggle between Block CN (Block China Traffic) and Allow CN (Allow China Traffic). The `info` command displays configuration details, VLESS links, and QR codes.

 * ⚙️ System Optimization:
   * Enables BBR + FQ congestion control.
   * Smart Swap allocation (Auto-adds 1GB Swap if RAM < 2GB).
   * Fail2ban integration with auto-detection of SSH port.
 * 🤖 Silent Installation: Handles all Debian/Ubuntu prompts automatically for a truly hands-free setup.

### 🛑 READ BEFORE INSTALLATION: Risk Assessment & Audit
> [!WARNING]
> **CRITICAL WARNING: This script performs aggressive system modifications.**
> **It is strongly recommended to run this ONLY on a FRESH, CLEAN VPS installation.**
> 
**1. 🔥 Network & Firewall Risks (High Severity)**
| Risk Item | Description | Potential Consequence |
| :--- | :--- | :--- |
| **Aggressive Firewall Reset** | The script executes `iptables -F` to flush ALL existing rules. | If you are running **Docker**, **Kubernetes**, or custom routing, **your network will break immediately**. |
| **Strict Default Policy** | Sets default input policy to `DROP`. Only SSH, 443, and 8443 are allowed. | If you use a non-standard SSH port (and the script fails to detect it) or a web panel, **you will be locked out**. |
| **Traffic Restriction (BT)** | **BitTorrent traffic is blocked** by internal routing rules. | You **cannot** use this node for Torrent/P2P downloads. (This is intended to protect your VPS from DMCA bans). |

**2. ⚙️ System Environment Risks (Medium Severity)**
* **Force Kill Processes**: The script executes `killall apt` at startup. If a system update is running in the background, this may corrupt the `dpkg` database.
* **Forced System Upgrade**: Includes `apt-get upgrade`, which may update the kernel. Do not run if your environment depends on a specific kernel version.
* **Swap Creation**: Automatically creates a 1GB Swap file if RAM < 2GB.

**3. 📱 Client Compatibility (Important)**
This script deploys two cutting-edge protocols. Ensure your client supports them:
* **Node 1 (Vision)**: Requires **Xray-core v1.8.0+** (e.g., v2rayN 6.x+, latest Shadowrocket).
* **Node 2 (xhttp)**: **Experimental/New Protocol** (Xray v1.8.24+). Only supported by very recent clients (e.g., v2rayN Pre-release, Shadowrocket, latest Nekobox).

### 🛠️ Installation Guide

**Prerequisites**:
* **OS**: Debian 10+ / Ubuntu 20.04+
* **User**: Root privileges required
* **Network**: Ports 443 and 8443 must be open and unused.

### 💻 Requirements
 * OS: Debian 10/11/12 or Ubuntu 20.04/22.04/24.04
 * Arch: x86_64 / amd64
 * Auth: Root access required
   
### 🚀 Installation
Replace YourUsername and YourRepo with your actual GitHub username and repository name:
```
bash <(curl -Ls https://github.com/ISFZY/Xray-Auto/raw/main/install.sh)

```
### 🗑️ Uninstall
To remove Xray and its associated configurations:
```
bash <(curl -sL https://github.com/ISFZY/Xray-Auto/raw/main/remove.sh)

```
### 🛠 Management
After installation, use the following commands:
| Command | Description |
|---|---|
| `mode` | Check current routing status (Block/Allow CN) |
| `info` | Retrieves node configuration, VLESS links, and QR codes|

### 📝 Configuration Details
After installation is complete, the script will automatically output connection information, including:
* **Node Configuration**: IP, Port, SNI, etc. (for manual input).
* **VLESS Link**: Can be directly copied and imported into clients (e.g., v2rayN, V2Box, Shadowrocket).
* **QR Code**: Scan with a mobile phone to connect directly.


### ⚠️ 免责声明 | Disclaimer
This project (including the script and related documentation) is open-sourced under the [**GNU General Public License v3.0 (GPL-3.0)**](https://github.com/ISFZY/Xray-Auto/blob/main/LICENSE). By downloading, installing, or using this project, you acknowledge that you have read and agreed to the following terms.

### 1. Educational and Research Purpose Only
This project is intended strictly for **network security research, server performance testing, and computer networking education**.
- The developer **does not encourage, support, or assist** in any activities that violate local laws or regulations.
- Users must strictly abide by the laws and regulations of the country/region where the server is located and where the user is based.

### 2. "AS IS" and No Warranty
Pursuant to Sections 15 and 16 of the GPL-3.0 license:
- This program is distributed in the hope that it will be useful, but **WITHOUT ANY WARRANTY**; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
- The developer shall not be held liable for any direct, indirect, incidental, special, or consequential damages (including but not limited to data loss, business interruption, server bans, or system crashes) arising from the use of this script.

### 3. System Modifications and Risks
- This script requires **root privileges** and performs deep system modifications, including but not limited to:
- Modifying system timezones and kernel parameters (enabling BBR, configuring Swap).
- Installing third-party dependencies and system services.
- Altering firewall rules (iptables/ip6tables) and SSH service configurations.
**Users assume full responsibility for any system instability or configuration conflicts.** It is strongly recommended to run this script on a clean installation of Debian/Ubuntu and to backup data before execution.

### 4. Third-Party Services
- This script retrieves core components and rule files (e.g., GeoIP/GeoSite) from third-party sources (e.g., GitHub, Loyalsoldier). The developer cannot guarantee the continuous availability or security of these external services.
- This tool acts solely as a network utility. The developer is not responsible for the legality, authenticity, or security of any content transmitted or accessed through this tool.

### 5. Consequences of Abuse
Any legal consequences or liabilities arising from the illegal use of this project (including but not limited to bypassing network censorship, launching cyberattacks, or disseminating illegal information) shall be borne solely by the user. The developer assumes no responsibility whatsoever.

---
*If you do not agree to any of the above terms, please stop downloading, installing, or using this project immediately.*



[Project maintained by ISFZY](https://github.com/ISFZY)

