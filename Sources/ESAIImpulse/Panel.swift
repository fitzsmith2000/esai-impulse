import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TrafficPanel: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject var model: TrafficModel
    @ObservedObject private var navigation: PanelNavigation
    @State private var customHex: String
    @State private var hexError = false
    @State private var loginDraft: String
    @State private var passwordDraft = ""
    @State private var credentialsSaved = false
    @State private var thresholdDraft: String
    private var accent: Color { model.accentColor }
    private func t(_ key: String, _ arguments: String...) -> String { model.translate(key,arguments:arguments) }
    init(model: TrafficModel) {
        self.model = model
        navigation = model.navigation
        _customHex = State(initialValue:model.accentHex)
        _loginDraft = State(initialValue:model.savedLogin)
        _thresholdDraft = State(initialValue:model.thresholdText)
    }

    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            header.padding(.horizontal,16).padding(.top,14).padding(.bottom,12)
            EsaiHairline()
            if navigation.showingSettings { settingsTabs.padding(.horizontal,16).padding(.top,12).padding(.bottom,4) }
            ScrollView(.vertical) {
                Group {
                    if navigation.showingSettings { settingsContent.padding(.vertical,16) }
                    else { dashboard.padding(.vertical,16) }
                }
                .padding(.horizontal,16)
                .frame(maxWidth:.infinity,alignment:.leading)
                .background(EsaiScrollChrome().allowsHitTesting(false))
            }
            .frame(maxWidth:.infinity,maxHeight:.infinity)
            EsaiHairline()
            footer
        }
        .frame(width:model.panelSize.width,height:model.panelSize.height,alignment:.topLeading)
        .background { if !model.glassBackground || reduceTransparency { EsaiSurface.panel } }
        .tint(accent)
        .preferredColorScheme(model.colorScheme)
        .environment(\.locale,model.resolvedLanguage.locale)
    }

    // MARK: Header
    private var levelColor: Color {
        switch model.level { case .depleted: return .red; case .low: return .orange; case .normal: return accent }
    }
    private var levelTitle: String {
        guard model.hasCredentials else { return t("未配置账号") }
        guard model.stats != nil else { return t("尚未刷新") }
        switch model.level { case .depleted: return t("流量用尽"); case .low: return t("流量偏低"); case .normal: return t("流量充足") }
    }
    private var header: some View {
        HStack(spacing:8) {
            if navigation.showingSettings {
                EsaiDetailBackButton(title:t("返回")) { navigation.showingSettings = false }
                Text(t("设置")).font(.title3.weight(.semibold))
            } else {
                if let url = Bundle.main.url(forResource:"StatusTemplate",withExtension:"pdf"), let image = NSImage(contentsOf:url) {
                    Image(nsImage:image).resizable().renderingMode(.template).foregroundStyle(accent).frame(width:19,height:19)
                }
                Text("ESAI Impulse").font(.title3.weight(.semibold))
                Text(levelTitle).font(.caption.weight(.semibold))
                    .foregroundStyle(model.stats == nil ? Color.secondary : levelColor)
                    .padding(.horizontal,7).padding(.vertical,3)
                    .background(model.stats == nil ? EsaiSurface.sunken : levelColor.opacity(0.12),in:Capsule())
            }
            Spacer(minLength:8)
            EsaiHeaderActionButton(title:t("刷新"),isLoading:model.refreshing,action:{ model.refresh() }) { Image(systemName:"arrow.clockwise") }
        }.fixedSize(horizontal:false,vertical:true)
    }

    // MARK: Dashboard
    private var dashboard: some View {
        VStack(alignment:.leading,spacing:16) {
            if !model.hasCredentials {
                VStack(alignment:.leading,spacing:10) {
                    Label(t("未配置账号"),systemImage:"key").font(.headline).foregroundStyle(accent)
                    Text(t("请在设置中填写 DataImpulse 账号和密码。")).font(.callout).foregroundStyle(.secondary)
                    Button(t("去设置")) { openSettings("account") }.esaiGlassButton(prominent:true)
                }.padding(14).frame(maxWidth:.infinity,alignment:.leading).esaiCard()
            }
            if let error = model.errorText {
                HStack(alignment:.top,spacing:8) {
                    Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment:.leading,spacing:2) {
                        Text(t("刷新失败")).font(.callout.weight(.semibold))
                        Text(error).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }
                    Spacer()
                }.padding(12).esaiCard(.sunken)
            }
            if let s = model.stats { statsView(s) }
            schedule
        }
    }

    private func statsView(_ s: TrafficStats) -> some View {
        let left = s.leftGB
        return VStack(alignment:.leading,spacing:14) {
            VStack(alignment:.leading,spacing:6) {
                Text(t("剩余流量")).font(.callout.weight(.medium)).foregroundStyle(.secondary)
                Text(formatTraffic(gb:left))
                    .font(.system(size:34,weight:.semibold,design:.rounded)).monospacedDigit()
                    .foregroundStyle(model.level == .normal ? Color.primary : levelColor)
                if left < 0 {
                    Text(t("已超额 %@",formatTraffic(gb:-left)))
                        .font(.caption.weight(.semibold)).foregroundStyle(.red)
                        .padding(.horizontal,7).padding(.vertical,3).background(Color.red.opacity(0.1),in:Capsule())
                }
            }
            VStack(alignment:.leading,spacing:6) {
                HStack {
                    Text(t("已用 %@",String(format:"%.1f%%",s.total > 0 ? s.used/s.total*100 : 0)))
                        .font(.callout.weight(.semibold)).monospacedDigit().foregroundStyle(model.level == .normal ? accent : levelColor)
                    Spacer()
                    Text(t("低于 %@ GB 时提醒",model.thresholdText)).font(.caption).foregroundStyle(.secondary)
                }
                GeometryReader { proxy in
                    ZStack(alignment:.leading) {
                        Capsule().fill(EsaiSurface.sunken)
                        let c = model.level == .normal ? accent : levelColor
                        Capsule().fill(LinearGradient(colors:[c,c.opacity(0.65)],startPoint:.leading,endPoint:.trailing))
                            .frame(width:max(4,proxy.size.width*s.usedFraction))
                    }
                }.frame(height:6)
            }
            HStack(spacing:8) {
                statCard(t("总流量"),formatTraffic(gb:TrafficStats.gb(s.total)))
                statCard(t("已用"),formatTraffic(gb:TrafficStats.gb(s.used)))
            }
        }
    }
    private func statCard(_ title: String, _ value: String) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).esaiCard()
    }
    private var schedule: some View {
        VStack(alignment:.leading,spacing:6) {
            EsaiHairline().padding(.bottom,6)
            HStack(spacing:5) {
                Image(systemName:"clock").foregroundStyle(accent)
                Text(model.lastRefresh.map { t("上次刷新：%@",model.timeText($0)) } ?? t("尚未刷新")).font(.caption.weight(.semibold))
                if let route = model.routeText, model.lastRefresh != nil {
                    Text(route).font(.system(size:10,weight:.semibold)).foregroundStyle(model.lastRoute == .direct ? accent : Color.secondary)
                        .padding(.horizontal,6).padding(.vertical,2)
                        .background(model.lastRoute == .direct ? accent.opacity(0.12) : EsaiSurface.sunken,in:Capsule())
                        .help(t(model.lastRoute == .direct ? "已绕过代理 / VPN，经物理网卡直连" : "经系统网络连接"))
                }
                Spacer()
            }
            HStack {
                Text(t("每 %@ 分钟自动刷新",String(model.intervalMinutes)))
                Spacer()
                if let next = model.nextRefresh { Text(t("下次：%@",model.timeText(next))) }
            }.font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Settings
    private var settingsTabs: some View {
        EsaiGlassSegments(selection:$navigation.settingsTab,options:[
            .init(id:"account",title:t("账号")), .init(id:"alerts",title:t("提醒")),
            .init(id:"appearance",title:t("外观")), .init(id:"general",title:t("通用"))
        ],accent:accent,label:t("设置"))
    }
    private var settingsContent: some View {
        VStack(alignment:.leading,spacing:18) {
            Group {
                if navigation.settingsTab == "account" { accountEditor }
                else if navigation.settingsTab == "alerts" { alertsEditor }
                else if navigation.settingsTab == "appearance" { appearanceEditor }
                else { generalSettings }
            }.animation(nil,value:navigation.settingsTab)
        }.onChange(of:model.accentHex) { customHex = $0; hexError = false }
    }

    private func field<F: View>(_ field: F) -> some View {
        field.textFieldStyle(.plain).font(.callout).padding(.horizontal,12).frame(height:34)
            .background(EsaiSurface.sunken,in:Capsule())
            .overlay(Capsule().strokeBorder(EsaiSurface.hairline.opacity(0.4),lineWidth:0.5))
    }
    private var accountEditor: some View {
        VStack(alignment:.leading,spacing:14) {
            VStack(alignment:.leading,spacing:4) {
                Text(t("DataImpulse 账号")).font(.headline)
                Text(t("填写代理套餐（Plan）的登录名和密码，与 gw.dataimpulse.com 使用的凭据相同。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            VStack(alignment:.leading,spacing:6) {
                Text(t("登录名")).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                field(TextField(t("登录名"),text:$loginDraft).disableAutocorrection(true))
                Text(t("密码")).font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.top,4)
                field(SecureField(model.hasCredentials ? "••••••••" : t("密码"),text:$passwordDraft).onSubmit(saveCredentials))
            }
            HStack {
                Button(t("保存并刷新"),action:saveCredentials).esaiGlassButton(prominent:true)
                    .disabled(loginDraft.trimmingCharacters(in:.whitespaces).isEmpty || passwordDraft.isEmpty)
                if model.hasCredentials {
                    Button(t("清除")) { model.clearCredentials(); loginDraft = ""; passwordDraft = ""; credentialsSaved = false }.esaiGlassButton()
                }
                Spacer()
                if credentialsSaved || model.hasCredentials {
                    Label(t("已保存到钥匙串"),systemImage:"checkmark.seal.fill").font(.caption.weight(.medium)).foregroundStyle(accent)
                }
            }
            if let error = model.errorText { Text(error).font(.caption).foregroundStyle(.orange) }
            EsaiHairline()
            VStack(alignment:.leading,spacing:8) {
                Text(t("连接方式")).font(.headline)
                EsaiAlignedMenu(selection:model.connectionMode.rawValue,choices:[
                    .init(id:"auto",title:t("自动（推荐）")), .init(id:"system",title:t("走系统网络")),
                    .init(id:"direct",title:t("直连（绕过代理 / VPN）"))
                ],label:t("连接方式"),accent:accent) { if let m = ConnectionMode(rawValue:$0) { model.setConnectionMode(m) } }
                    .frame(height:34).esaiGlassControl()
                Text(t("自动：先走系统网络，失败时经物理网卡直连 DataImpulse，绕过代理 / VPN 的 TUN。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            Label(t("账号和密码仅保存在 macOS 钥匙串中，不会写入文件或日志。"),systemImage:"lock.shield")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                .padding(12).frame(maxWidth:.infinity,alignment:.leading).esaiCard(.sunken)
        }
    }
    private func saveCredentials() {
        guard !loginDraft.trimmingCharacters(in:.whitespaces).isEmpty, !passwordDraft.isEmpty else { return }
        model.saveCredentials(login:loginDraft,password:passwordDraft)
        passwordDraft = ""; credentialsSaved = true
    }

    private var alertsEditor: some View {
        VStack(alignment:.leading,spacing:16) {
            VStack(alignment:.leading,spacing:8) {
                Text(t("刷新间隔")).font(.headline)
                EsaiGlassSegments(selection:Binding(get:{String(model.intervalMinutes)},set:{ model.setInterval(Int($0) ?? 15) }),
                    options:[5,15,30,60].map { .init(id:String($0),title:t("%@ 分钟",String($0))) },accent:accent,label:t("刷新间隔"))
            }
            EsaiHairline()
            VStack(alignment:.leading,spacing:10) {
                Text(t("低流量提醒")).font(.headline)
                HStack {
                    Text(t("提醒阈值")).font(.callout.weight(.medium))
                    Spacer()
                    field(TextField("200",text:$thresholdDraft).multilineTextAlignment(.trailing).monospacedDigit()
                        .onSubmit(applyThreshold)).frame(width:96)
                    Text("GB").font(.callout).foregroundStyle(.secondary)
                    Button(t("应用"),action:applyThreshold).font(.caption).esaiGlassButton()
                }
                HStack(spacing:6) {
                    ForEach([50,100,200,500],id:\.self) { v in
                        Button("\(v) GB") { thresholdDraft = String(v); applyThreshold() }.font(.caption).esaiGlassButton(prominent:Int(model.thresholdGB) == v && model.thresholdGB == Double(v))
                    }
                }
                Text(t("剩余低于阈值时，状态栏数字变为橙色并发送一次系统通知；用尽时变为红色并再通知一次。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    .padding(12).frame(maxWidth:.infinity,alignment:.leading).esaiCard(.sunken)
                Button(t("打开通知设置")) { model.openNotificationSettings() }.font(.caption).esaiGlassButton()
            }
        }
    }
    private func applyThreshold() {
        if let v = Double(thresholdDraft.replacingOccurrences(of:",",with:".")), v > 0 { model.setThreshold(v) }
        thresholdDraft = model.thresholdText
    }

    /// Settings → 外观 without the scroll host, for `--render-settings`.
    var appearanceForRender: some View {
        appearanceEditor.padding(16).frame(width:model.panelSize.width,alignment:.topLeading)
            .tint(accent).preferredColorScheme(model.colorScheme).environment(\.locale,model.resolvedLanguage.locale)
    }
    private var appearanceEditor: some View {
        VStack(alignment:.leading,spacing:16) {
            VStack(alignment:.leading,spacing:8) {
                Text(t("状态栏样式")).font(.headline)
                EsaiGlassSegments(selection:Binding(get:{model.statusStyle.rawValue},set:{ if let v = StatusStyle(rawValue:$0) { model.setStatusStyle(v) } }),options:[
                    .init(id:"iconText",title:t("图标+数字")), .init(id:"icon",title:t("仅图标")), .init(id:"compact",title:t("两行紧凑"))
                ],accent:accent,label:t("状态栏样式"))
                Text(t("环的长度 = 剩余 ÷ 提醒阈值；偏低变橙，用尽变红并带角标。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            EsaiHairline()
            VStack(alignment:.leading,spacing:10) {
                HStack {
                    Text(t("状态栏")).font(.headline)
                    Spacer()
                    Button(t("恢复默认")) { model.resetTypography() }.font(.caption).esaiGlassButton()
                        .disabled(model.typography == StatusTypography.defaults)
                }
                HStack(spacing:8) {
                    ForEach([false,true],id:\.self) { dark in
                        Image(nsImage:StatusRenderer.previewImage(model.previewSnapshot,style:model.statusStyle,typography:model.typography,dark:dark))
                            .clipShape(RoundedRectangle(cornerRadius:6,style:.continuous))
                    }
                    Spacer(minLength:0)
                }.accessibilityLabel(t("状态栏预览"))
                typoSlider("字号",\.fontSize,StatusTypography.fontRange)
                HStack(spacing:10) {
                    Text(t("字重")).font(.callout.weight(.medium)).frame(width:96,alignment:.leading)
                    EsaiGlassSegments(selection:Binding(get:{model.typography.weight.rawValue},set:{ var v = model.typography; v.weight = StatusWeight(rawValue:$0) ?? .semibold; model.setTypography(v) }),
                        options:[.init(id:"regular",title:t("常规")),.init(id:"medium",title:t("中等")),.init(id:"semibold",title:t("半粗"))],accent:accent,label:t("字重"))
                }
                typoSlider("图标大小",\.iconSize,StatusTypography.iconRange)
                typoSlider("图标与文字间距",\.spacing,StatusTypography.spacingRange)
                typoSlider("两行字号",\.compactFontSize,StatusTypography.compactRange)
                offsetSlider
                Text(t("默认值：文字 10.5 pt 常规、图标 19 pt、间距 9 pt、两行 8.5 pt、偏移 0。修改即时生效。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.padding(12).esaiCard(.sunken)
            configsSection.padding(12).esaiCard(.sunken)
            EsaiHairline()
            VStack(alignment:.leading,spacing:8) {
                Text(t("外观模式")).font(.headline)
                EsaiGlassSegments(selection:Binding(get:{model.appearance},set:{model.setAppearance($0)}),options:[
                    .init(id:"system",title:t("跟随系统")),
                    .init(id:"light",title:t("浅色")),
                    .init(id:"dark",title:t("深色"))
                ],accent:accent,label:t("外观模式"))
            }
            VStack(alignment:.leading,spacing:8) {
                EsaiSwitchRow(title:t("透明玻璃背景"),isOn:Binding(get:{model.glassBackground},set:{model.setGlassBackground($0)}))
                Text(t("面板会透出桌面背景；关闭后使用实色面板。"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal:false,vertical:true)
            }
            .padding(12)
            .esaiCard(.sunken)
            EsaiHairline()
            VStack(alignment:.leading,spacing:12) {
                VStack(alignment:.leading,spacing:4) {
                    Text(t("强调色")).font(.headline)
                    Text(t("选择经典颜色，或调出属于你的 esai。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:4),count:6),spacing:8) {
                    ForEach(AccentPreset.choices) { preset in
                        Button { model.setAccent(preset.hex) } label: {
                            VStack(spacing:6) {
                                let rgb = AccentRGB(hex:preset.hex)!
                                Circle().fill(Color(red:rgb.red,green:rgb.green,blue:rgb.blue))
                                    .frame(width:29,height:29)
                                    .overlay {
                                        if model.accentHex == preset.hex {
                                            Image(systemName:"checkmark").font(.system(size:12,weight:.bold)).foregroundStyle(.white)
                                        }
                                    }
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(model.accentHex == preset.hex ? accent : Color.clear,lineWidth:1.5))
                                Text(t(preset.name)).font(.system(size:10)).foregroundStyle(.secondary)
                            }.frame(maxWidth:.infinity)
                        }.buttonStyle(.plain).help(t(preset.name))
                            .accessibilityLabel(t(preset.name)).accessibilityAddTraits(model.accentHex == preset.hex ? .isSelected : [])
                    }
                }
                HStack {
                    ColorPicker(t("自定义颜色"),selection:Binding(get:{model.selectedAccent},set:{model.setAccentColor($0)}),supportsOpacity:false)
                        .font(.caption).accessibilityLabel(t("自定义强调色取色器"))
                    Spacer(minLength:8)
                    TextField("#RRGGBB",text:$customHex)
                        .font(.system(size:11,design:.monospaced)).textFieldStyle(.plain)
                        .padding(.horizontal,10).frame(width:86,height:30)
                        .background(EsaiSurface.sunken,in:Capsule())
                        .onSubmit { applyCustomHex() }.accessibilityLabel(t("强调色 HEX 色值"))
                    Button(t("应用")) { applyCustomHex() }.font(.caption).esaiGlassButton()
                }
                if hexError { Text(t("请输入六位 HEX 色值，例如 #2878ED。")).font(.caption).foregroundStyle(.red) }
                VStack(alignment:.leading,spacing:8) {
                    HStack {
                        Label(t("强调色预览"),systemImage:"checkmark.circle.fill").font(.callout.weight(.semibold)).foregroundStyle(accent)
                        Spacer()
                        Text(t("流量充足")).font(.caption.weight(.medium)).foregroundStyle(accent)
                            .padding(.horizontal,8).padding(.vertical,4).background(accent.opacity(0.12),in:Capsule())
                    }
                    Capsule().fill(accent).frame(height:5)
                    Text(t("实时应用并保存；浅色和深色模式自动调整可读性。"))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }.padding(12).esaiCard(.sunken)
            }
        }
    }

    private func typoSlider(_ title: String, _ key: WritableKeyPath<StatusTypography,Double>, _ range: ClosedRange<Double>) -> some View {
        HStack(spacing:10) {
            Text(t(title)).font(.callout.weight(.medium)).frame(width:96,alignment:.leading).lineLimit(1).minimumScaleFactor(0.8)
            Slider(value:Binding(get:{ model.typography[keyPath:key] },set:{ var v = model.typography; v[keyPath:key] = $0; model.setTypography(v) }),in:range,step:0.5)
                .controlSize(.small).accessibilityLabel(t(title))
            Text(String(format:"%.1f pt",model.typography[keyPath:key])).font(.caption).monospacedDigit()
                .foregroundStyle(.secondary).frame(width:48,alignment:.trailing)
        }
    }

    /// 「文字上下偏移」: -3…+3 pt in 0.25 pt steps, positive = up; zero tick in the middle, double-click or ↺ resets.
    private var offsetSlider: some View {
        let range = StatusTypography.offsetRange
        let value = model.typography.textOffset
        func set(_ v: Double) { var t = model.typography; t.textOffset = v; model.setTypography(t) }
        return HStack(spacing:10) {
            Text(t("文字上下偏移")).font(.callout.weight(.medium)).frame(width:96,alignment:.leading).lineLimit(1).minimumScaleFactor(0.8)
            Slider(value:Binding(get:{ value },set:{ set($0) }),in:range,step:0.25)
                .controlSize(.small).accessibilityLabel(t("文字上下偏移"))
                .overlay(alignment:.center) {
                    // Zero point marker (slider is symmetric, so 0 is the horizontal centre).
                    Capsule().fill(Color.secondary.opacity(0.55)).frame(width:1.5,height:12).offset(y:-9).allowsHitTesting(false)
                }
                .onTapGesture(count:2) { set(0) }
                .help(t("双击滑块归零；正值上移，负值下移"))
            Button { set(0) } label: { Image(systemName:"arrow.counterclockwise").font(.caption2) }
                .buttonStyle(.plain).foregroundStyle(value == 0 ? Color.secondary.opacity(0.35) : accent)
                .disabled(value == 0).help(t("归零")).accessibilityLabel(t("归零"))
            Text(value == 0 ? "0 pt" : String(format:"%+.2f pt",value)).font(.caption).monospacedDigit()
                .foregroundStyle(.secondary).frame(width:48,alignment:.trailing)
        }
    }

    // MARK: Saved status bar configurations
    private var configsSection: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Text(t("已保存的配置")).font(.headline)
                Spacer()
                if EsaiRenderMode.offscreen { Image(systemName:"square.and.arrow.up.on.square").foregroundStyle(accent) } else { Menu {
                    Button(t("导出配置…")) { exportConfigs() }.disabled(model.statusConfigs.count < 2)
                    Button(t("导入配置…")) { importConfigs() }
                } label: { Image(systemName:"square.and.arrow.up.on.square") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(t("导入 / 导出 JSON")) }
            }
            VStack(spacing:4) {
                ForEach(model.statusConfigs) { c in configRow(c) }
            }
            HStack(spacing:8) {
                Button(t("保存为配置…")) { saveAsConfig() }.font(.caption).esaiGlassButton(prominent:true)
                Button(t("覆盖保存")) { model.overwriteActiveConfig() }.font(.caption).esaiGlassButton()
                    .disabled(!(model.activeConfigModified && model.activeConfig?.isBuiltIn == false))
                Spacer(minLength:0)
            }
            Text(t("配置包含样式、字号、字重、图标大小、间距、两行字号和文字偏移。点击即可切换；「默认」为内置配置，不可删除。"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
    private func configSummary(_ c: StatusConfig) -> String {
        let style = c.style == .iconText ? t("图标+数字") : c.style == .icon ? t("仅图标") : t("两行紧凑")
        let w = c.typography.weight == .regular ? t("常规") : c.typography.weight == .medium ? t("中等") : t("半粗")
        let ty = c.typography
        var parts = [style, String(format:"%g pt",ty.fontSize)+" "+w, t("图标 %@",String(format:"%g",ty.iconSize)), t("间距 %@",String(format:"%g",ty.spacing))]
        if ty.textOffset != 0 { parts.append(t("偏移 %@",String(format:"%+g",ty.textOffset))) }
        return parts.joined(separator:" · ")
    }
    private func configRow(_ c: StatusConfig) -> some View {
        let active = model.activeConfigID == c.id
        return HStack(spacing:8) {
            Button { model.applyConfig(c.id) } label: {
                HStack(spacing:8) {
                    Image(systemName:active ? "checkmark.circle.fill" : "circle").foregroundStyle(active ? accent : Color.secondary.opacity(0.5))
                    VStack(alignment:.leading,spacing:1) {
                        HStack(spacing:4) {
                            Text(model.configDisplayName(c)).font(.callout.weight(active ? .semibold : .regular)).lineLimit(1)
                            if c.isBuiltIn { Image(systemName:"lock.fill").font(.system(size:8)).foregroundStyle(.secondary) }
                            if active && model.activeConfigModified { Text(t("已修改")).font(.caption2).foregroundStyle(.orange) }
                        }
                        Text(configSummary(c)).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    }
                    Spacer(minLength:0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(model.configDisplayName(c)).accessibilityAddTraits(active ? .isSelected : [])
            if !c.isBuiltIn && EsaiRenderMode.offscreen { Image(systemName:"ellipsis.circle").foregroundStyle(.secondary) }
            else if !c.isBuiltIn {
                Menu {
                    Button(t("重命名…")) { renameConfig(c) }
                    Divider()
                    Button(t("删除…"),role:.destructive) { deleteConfig(c) }
                } label: { Image(systemName:"ellipsis.circle").foregroundStyle(.secondary) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
        }
        .padding(.horizontal,8).padding(.vertical,6)
        .background(RoundedRectangle(cornerRadius:8,style:.continuous).fill(active ? accent.opacity(0.12) : Color.clear))
    }
    private func promptName(title: String, initial: String, confirm: String) -> String? {
        let alert = NSAlert(); alert.messageText = title
        let field = NSTextField(frame:NSRect(x:0,y:0,width:240,height:24)); field.stringValue = initial
        alert.accessoryView = field
        alert.addButton(withTitle:confirm); alert.addButton(withTitle:t("取消"))
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps:true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let v = field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }
    private func saveAsConfig() {
        if let name = promptName(title:t("保存为配置"),initial:model.suggestedConfigName,confirm:t("保存")) { model.saveConfig(named:name) }
    }
    private func renameConfig(_ c: StatusConfig) {
        if let name = promptName(title:t("重命名配置"),initial:c.name,confirm:t("重命名")) { model.renameConfig(c.id,to:name) }
    }
    private func deleteConfig(_ c: StatusConfig) {
        let alert = NSAlert(); alert.alertStyle = .warning
        alert.messageText = t("删除配置「%@」？",c.name); alert.informativeText = t("此操作无法撤销。")
        alert.addButton(withTitle:t("删除")).hasDestructiveAction = true
        alert.addButton(withTitle:t("取消"))
        NSApp.activate(ignoringOtherApps:true)
        if alert.runModal() == .alertFirstButtonReturn { model.deleteConfig(c.id) }
    }
    private func exportConfigs() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "esai-impulse-statusbar-configs.json"; panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps:true)
        if panel.runModal() == .OK, let url = panel.url { try? model.exportConfigs().write(to:url) }
    }
    private func importConfigs() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps:true)
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf:url) else { return }
        if !model.importConfigs(data) {
            let a = NSAlert(); a.messageText = t("无法导入：文件不是有效的配置 JSON。"); a.runModal()
        }
    }

    private func applyCustomHex() {
        guard AccentRGB(hex:customHex) != nil else { hexError = true; return }
        model.setAccent(customHex); customHex = model.accentHex; hexError = false
    }

    private var generalSettings: some View {
        VStack(alignment:.leading,spacing:18) {
            VStack(alignment:.leading,spacing:10) {
                Text(t("语言")).font(.headline)
                EsaiAlignedMenu(selection:model.language.rawValue,choices:AppLanguage.allCases.map {
                    .init(id:$0.rawValue,title:$0 == .system ? t("跟随系统") : $0.nativeName)
                },label:t("界面语言"),accent:accent) {
                    if let language = AppLanguage(rawValue:$0) { model.setLanguage(language) }
                }.frame(height:34).esaiGlassControl()
                Text(t("跟随系统会自动使用电脑的首选语言，切换立即生效。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                Text(t("当前语言：%@",model.resolvedLanguage.nativeName)).font(.caption).foregroundStyle(.secondary)
            }
            EsaiHairline()
            VStack(alignment:.leading,spacing:8) {
                Text(t("通用")).font(.headline)
                VStack(alignment:.leading,spacing:12) {
                    EsaiSwitchRow(title:t("登录时启动"),isOn:Binding(get:{model.loginEnabled},set:{ if $0 != model.loginEnabled { model.toggleLogin() } }))
                    if let message = model.loginMessage {
                        Text(message).font(.caption).foregroundStyle(.orange)
                        Button(t("打开登录项设置")) { model.openLoginSettings() }.font(.caption).esaiGlassButton()
                    }
                }.frame(maxWidth:.infinity,alignment:.leading).padding(12).esaiCard()
            }
            EsaiHairline()
            HStack(spacing:8) {
                Button { openProjectPage() } label: {
                    HStack(spacing:8) {
                        if let image = NSImage(named:"AppIcon") { Image(nsImage:image).resizable().frame(width:36,height:36) }
                        VStack(alignment:.leading,spacing:2) {
                            Text("ESAI Impulse").font(.callout.weight(.medium))
                            Text(t("版本 %@",Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1")).font(.caption).foregroundStyle(.secondary)
                        }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).pointingHandCursor().help(t("在 GitHub 上查看项目"))
                Spacer()
                Button { openProjectPage() } label: {
                    Label("GitHub",systemImage:"arrow.up.right.square").font(.caption.weight(.medium))
                }.buttonStyle(.plain).foregroundStyle(accent).pointingHandCursor()
                    .help(t("在 GitHub 上查看项目")).accessibilityLabel(t("在 GitHub 上查看项目"))
                Button(t("开源许可")) {
                    if let url = Bundle.main.url(forResource:"THIRD_PARTY_NOTICES",withExtension:"md") { NSWorkspace.shared.open(url) }
                }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).pointingHandCursor()
            }
        }
    }

    private func openProjectPage() {
        if let url = URL(string:"https://github.com/fitzsmith2000/esai-impulse") { NSWorkspace.shared.open(url) }
    }

    private func openSettings(_ tab: String) { navigation.settingsTab = tab; navigation.showingSettings = true }

    private var footer: some View {
        HStack {
            if !navigation.showingSettings {
                EsaiFooterGhostButton(title:t("设置"),systemImage:"slider.horizontal.3",role:.normal,help:t("打开设置")) { openSettings("account") }
            } else {
                Text("ESAI Impulse").font(.callout.weight(.medium)).foregroundStyle(.tertiary)
            }
            Spacer()
            EsaiFooterGhostButton(title:t("退出"),systemImage:"power",role:.destructive,help:t("退出 ESAI Impulse")) { NSApp.terminate(nil) }
        }.padding(.horizontal,16).padding(.vertical,8)
    }
}
