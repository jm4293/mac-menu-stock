// StockBar — 맥 메뉴바 한국 주식/지수 표시 앱
// LS증권 OpenAPI 사용
//
// 빌드:  ./build.sh   (또는 Xcode에서 Package.swift 열고 ⌘R)
// 설정:  ~/.stockbar/config.json
//
// 색상 규칙(한국식): 상승=빨강, 하락=파랑, 보합=기본색
// 메뉴가 열린(하이라이트) 상태에서는 자동으로 흰색 처리.

import Cocoa

// MARK: - 설정

struct Config {
    var appkey: String = ""
    var appsecret: String = ""
    var refreshSeconds: Int = 5
    var showLabels: Bool = true      // 종목명 표시 여부 (false면 숫자만)
    var showChange: Bool = true      // 등락(화살표+%) 표시 여부
    var useColor: Bool = true        // 등락 색상 사용 여부
    var indices: [String] = ["001"]  // 업종코드 (코스피=001, 코스닥=301)
    var stocks: [String] = ["005930"]// 종목코드 (삼성전자=005930)
    var debug: Bool = false          // 원본 응답 로그 기록
    var useWebSocket: Bool = true    // 실시간 웹소켓 사용(주식 체결)
    // 실시간 체결 코드: US3=통합(KRX+NXT), S3_=KOSPI, K3_=KOSDAQ, NS3=NXT
    var realtimeCodes: [String] = ["US3"]

    var isConfigured: Bool {
        !appkey.isEmpty && !appkey.contains("여기에") &&
        !appsecret.isEmpty && !appsecret.contains("여기에")
    }
}

func configDirURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".stockbar")
}
func configFileURL() -> URL { configDirURL().appendingPathComponent("config.json") }
func debugLogURL() -> URL { configDirURL().appendingPathComponent("debug.log") }

func anyString(_ v: Any?) -> String? {
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return nil
}
func anyToDouble(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
        return t.isEmpty ? nil : Double(t)
    }
    return nil
}
func anyToInt(_ v: Any?) -> Int? {
    if let n = v as? NSNumber { return n.intValue }
    if let i = v as? Int { return i }
    if let s = v as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
    if let d = anyToDouble(v) { return Int(d) }
    return nil
}

// config.json 읽기 (없으면 템플릿 생성). 구버전 키(indexCode/stockCode)도 호환.
func loadConfig() -> Config? {
    let url = configFileURL()
    let fm = FileManager.default
    if !fm.fileExists(atPath: url.path) {
        try? fm.createDirectory(at: configDirURL(), withIntermediateDirectories: true)
        var tpl = Config()
        tpl.appkey = "여기에_APP_KEY_입력"
        tpl.appsecret = "여기에_APP_SECRET_입력"
        saveConfig(tpl)
        return nil
    }
    guard let data = try? Data(contentsOf: url),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }
    var cfg = Config()
    cfg.appkey = (obj["appkey"] as? String) ?? ""
    cfg.appsecret = (obj["appsecret"] as? String) ?? ""
    cfg.refreshSeconds = anyToInt(obj["refreshSeconds"]) ?? 5
    cfg.showLabels = (obj["showLabels"] as? Bool) ?? true
    cfg.showChange = (obj["showChange"] as? Bool) ?? true
    cfg.useColor = (obj["useColor"] as? Bool) ?? true
    cfg.debug = (obj["debug"] as? Bool) ?? false
    cfg.useWebSocket = (obj["useWebSocket"] as? Bool) ?? true
    if let arr = obj["realtimeCodes"] as? [String], !arr.isEmpty { cfg.realtimeCodes = arr }

    if let arr = obj["indices"] as? [String], !arr.isEmpty { cfg.indices = arr }
    else if let one = obj["indexCode"] as? String { cfg.indices = [one] }
    if let arr = obj["stocks"] as? [String], !arr.isEmpty { cfg.stocks = arr }
    else if let one = obj["stockCode"] as? String { cfg.stocks = [one] }

    return cfg.isConfigured ? cfg : nil
}

func saveConfig(_ cfg: Config) {
    let dict: [String: Any] = [
        "appkey": cfg.appkey,
        "appsecret": cfg.appsecret,
        "refreshSeconds": cfg.refreshSeconds,
        "showLabels": cfg.showLabels,
        "showChange": cfg.showChange,
        "useColor": cfg.useColor,
        "indices": cfg.indices,
        "stocks": cfg.stocks,
        "debug": cfg.debug,
        "useWebSocket": cfg.useWebSocket,
        "realtimeCodes": cfg.realtimeCodes
    ]
    try? FileManager.default.createDirectory(at: configDirURL(), withIntermediateDirectories: true)
    if let data = try? JSONSerialization.data(withJSONObject: dict,
                                              options: [.prettyPrinted, .sortedKeys]) {
        try? data.write(to: configFileURL())
    }
}

// MARK: - 데이터 모델

struct Quote {
    var code: String
    var name: String
    var price: Double
    var diff: Double      // 등락율(%)
    var sign: String      // 2 상승, 3 보합, 5 하락
    var isIndex: Bool
    var base: Double      // 기준가(전일종가/전일지수) — 등락 계산 기준
}

// 기준가와 현재가로 등락율/부호를 계산해 Quote 생성
func makeQuote(code: String, name: String, price: Double, base: Double, isIndex: Bool) -> Quote {
    var diff = 0.0
    var sign = "3"
    if base > 0, price > 0 {
        let ch = price - base
        diff = abs(ch / base * 100)
        sign = ch > 0 ? "2" : (ch < 0 ? "5" : "3")
    }
    return Quote(code: code, name: name, price: price, diff: diff, sign: sign, isIndex: isIndex, base: base)
}

func signString(_ v: Any?) -> String {
    if let s = v as? String { return s.trimmingCharacters(in: .whitespaces) }
    if let n = v as? NSNumber { return String(n.intValue) }
    return "3"
}
func arrow(forSign sign: String) -> String {
    switch sign {
    case "1", "2": return "▲"
    case "4", "5": return "▼"
    default:        return "–"
    }
}
func quoteColor(forSign sign: String) -> NSColor {
    switch sign {
    case "1", "2": return NSColor.systemRed
    case "4", "5": return NSColor.systemBlue
    default:        return NSColor.labelColor
    }
}
func formatNumber(_ v: Double, decimals: Int) -> String {
    let nf = NumberFormatter()
    nf.numberStyle = .decimal
    nf.minimumFractionDigits = decimals
    nf.maximumFractionDigits = decimals
    return nf.string(from: NSNumber(value: v)) ?? String(v)
}
func firstDouble(_ dict: [String: Any], _ keys: [String]) -> Double? {
    for k in keys { if let v = anyToDouble(dict[k]) { return v } }
    return nil
}

// MARK: - LS OpenAPI 클라이언트

enum APIError: Error, CustomStringConvertible {
    case http(Int, String)
    case parse(String)
    var description: String {
        switch self {
        case .http(let c, let b): return "HTTP \(c) \(b.prefix(120))"
        case .parse(let w):       return "응답 파싱 실패(\(w))"
        }
    }
}

final class LSClient {
    private let base = "https://openapi.ls-sec.co.kr:8080"
    private let appkey: String
    private let appsecret: String
    private var cachedToken: String?
    private var tokenExpiry: Date = .distantPast

    var lastResponses: [String: String] = [:]   // 디버그용 원본 응답
    var lastIndexBlock: [String: Any]?           // 마지막 t1511OutBlock (필드 진단용)
    private var stockMaster: [(code: String, name: String)] = []

    init(appkey: String, appsecret: String) {
        self.appkey = appkey
        self.appsecret = appsecret
    }

    func accessToken() async throws -> String { try await token() }

    private func token() async throws -> String {
        if let t = cachedToken, Date() < tokenExpiry { return t }
        var req = URLRequest(url: URL(string: base + "/oauth2/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = ("grant_type=client_credentials&appkey=\(appkey)&appsecretkey=\(appsecret)&scope=oob")
            .data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard code == 200 else { throw APIError.http(code, String(data: data, encoding: .utf8) ?? "") }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tok = obj["access_token"] as? String else { throw APIError.parse("token") }
        cachedToken = tok
        tokenExpiry = Date().addingTimeInterval((anyToDouble(obj["expires_in"]) ?? 86400) - 60)
        return tok
    }

    private func query(path: String, trCd: String, inBlock: String,
                       params: [String: Any]) async throws -> [String: Any] {
        let tok = try await token()
        var req = URLRequest(url: URL(string: base + path)!)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer " + tok, forHTTPHeaderField: "authorization")
        req.setValue(trCd, forHTTPHeaderField: "tr_cd")
        req.setValue("N", forHTTPHeaderField: "tr_cont")
        req.setValue("", forHTTPHeaderField: "tr_cont_key")
        req.httpBody = try JSONSerialization.data(withJSONObject: [inBlock: params])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        lastResponses[trCd] = String(data: data, encoding: .utf8) ?? ""
        guard code == 200 else { throw APIError.http(code, lastResponses[trCd] ?? "") }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.parse("json")
        }
        return obj
    }

    // 주식 현재가(시세) — t1102
    func fetchStock(code: String) async throws -> Quote {
        let obj = try await query(path: "/stock/market-data", trCd: "t1102",
                                  inBlock: "t1102InBlock", params: ["shcode": code])
        guard let out = obj["t1102OutBlock"] as? [String: Any] else { throw APIError.parse("t1102OutBlock") }
        let price = firstDouble(out, ["price"]) ?? 0
        var base = firstDouble(out, ["recprice", "jnilclose"]) ?? 0
        if base == 0 { base = price - (firstDouble(out, ["change"]) ?? 0) }
        return makeQuote(code: code, name: (out["hname"] as? String) ?? code,
                         price: price, base: base, isIndex: false)
    }

    // 업종 현재가(지수) — t1511. 지수/등락율 필드명이 환경마다 달라 다중 후보로 탐색.
    func fetchIndex(code: String) async throws -> Quote {
        let obj = try await query(path: "/indtp/market-data", trCd: "t1511",
                                  inBlock: "t1511InBlock", params: ["upcode": code])
        let out = (obj["t1511OutBlock"] as? [String: Any]) ?? (obj["t1511OutBlock1"] as? [String: Any]) ?? [:]
        lastIndexBlock = out.isEmpty ? obj : out
        // 실제 LS 응답: 현재지수=pricejisu, 등락율=diffjisu, 전일대비=change, 부호=sign
        let price = firstDouble(out, ["pricejisu", "jisu", "price", "sijisu"]) ?? 0
        var base = firstDouble(out, ["jniljisu"]) ?? 0
        if base == 0 { base = price - (firstDouble(out, ["change", "diffval"]) ?? 0) }
        let name = (code == "001") ? "코스피" : (code == "301" ? "코스닥" : "지수\(code)")
        return makeQuote(code: code, name: name, price: price, base: base, isIndex: true)
    }

    // 종목명/코드 검색 — t8436 주식종목조회 (전체 마스터 캐시 후 부분일치)
    func searchStocks(_ keyword: String) async throws -> [(code: String, name: String)] {
        if stockMaster.isEmpty {
            let obj = try await query(path: "/stock/etc", trCd: "t8436",
                                      inBlock: "t8436InBlock", params: ["gubun": "0"])
            guard let arr = obj["t8436OutBlock"] as? [[String: Any]] else { throw APIError.parse("t8436OutBlock") }
            stockMaster = arr.compactMap {
                guard let c = anyString($0["shcode"]), let n = anyString($0["hname"]) else { return nil }
                return (c, n)
            }
        }
        let q = keyword.trimmingCharacters(in: .whitespaces)
        return stockMaster.filter { $0.name.contains(q) }
            .sorted { $0.name.count < $1.name.count }
    }
}

// MARK: - LS 실시간 웹소켓

final class LSWebSocket: NSObject, URLSessionWebSocketDelegate {
    private let url = URL(string: "wss://openapi.ls-sec.co.kr:9443/websocket")!
    private let token: String
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var subs: [(cd: String, key: String)] = []
    private var closed = false
    private var pingTimer: Timer?

    var onMessage: ((_ trCd: String, _ trKey: String, _ body: [String: Any]) -> Void)?
    var onRaw: ((String) -> Void)?

    init(token: String) { self.token = token; super.init() }

    func connect(_ subscriptions: [(String, String)]) {
        subs = subscriptions.map { (cd: $0.0, key: $0.1) }
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        task = session.webSocketTask(with: url)
        task?.resume()
        receive()
    }

    func close() {
        closed = true
        pingTimer?.invalidate()
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol proto: String?) {
        for s in subs { send(trType: "3", trCd: s.cd, trKey: s.key) }
        DispatchQueue.main.async { [weak self] in
            self?.pingTimer?.invalidate()
            self?.pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                self?.task?.sendPing { _ in }
            }
        }
    }

    private func send(trType: String, trCd: String, trKey: String) {
        let msg: [String: Any] = ["header": ["token": token, "tr_type": trType],
                                  "body": ["tr_cd": trCd, "tr_key": trKey]]
        guard let d = try? JSONSerialization.data(withJSONObject: msg),
              let s = String(data: d, encoding: .utf8) else { return }
        task?.send(.string(s)) { _ in }
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let msg):
                if case .string(let text) = msg { self.handle(text) }
                if !self.closed { self.receive() }
            case .failure:
                guard !self.closed else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self = self, !self.closed else { return }
                    self.task = self.session.webSocketTask(with: self.url)
                    self.task?.resume()
                    self.receive()
                }
            }
        }
    }

    private func handle(_ text: String) {
        onRaw?(text)
        guard let d = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        let header = obj["header"] as? [String: Any]
        let trCd = (header?["tr_cd"] as? String) ?? ""
        let trKey = (header?["tr_key"] as? String) ?? ""
        if let body = obj["body"] as? [String: Any], !body.isEmpty {
            onMessage?(trCd, trKey, body)
        }
    }
}

// MARK: - 앱 델리게이트

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var client: LSClient?
    var config: Config?
    var timer: Timer?

    var quotes: [Quote] = []
    var lastError: String?
    var lastUpdate: Date?
    var menuIsOpen = false

    // 웹소켓 실시간
    var ws: LSWebSocket?
    var liveTick = Set<String>()      // 실시간 체결이 들어온 종목코드
    var wsLog: [String] = []          // 실시간 원본 메시지(진단용)

    // 값 변동 시 잠깐 색을 깜빡이기 위한 상태
    var prevPrices: [String: Double] = [:]
    var flash: [String: (color: NSColor, until: Date)] = [:]
    var flashTimer: Timer?
    let flashDuration: TimeInterval = 1.3
    // 연한 깜빡임 색 (상승=연한 빨강, 하락=연한 파랑)
    let flashUp = NSColor(srgbRed: 1.0, green: 0.55, blue: 0.55, alpha: 1.0)
    let flashDown = NSColor(srgbRed: 0.55, green: 0.76, blue: 1.0, alpha: 1.0)

    let barFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupEditMenu()   // ⌘C/⌘V/⌘X/⌘A 단축키 활성화 (입력창 복사·붙여넣기)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "주식 로딩…"
        reload()
    }

    // 메뉴바 전용 앱에도 표준 편집 단축키가 동작하도록 Edit 메뉴 구성
    func setupEditMenu() {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "다시 실행", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "전체 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = mainMenu
    }

    func reload() {
        timer?.invalidate()
        ws?.close(); ws = nil
        liveTick = []
        config = loadConfig()
        if let cfg = config {
            client = LSClient(appkey: cfg.appkey, appsecret: cfg.appsecret)
            let interval = TimeInterval(max(2, cfg.refreshSeconds))
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.refresh()
            }
            refresh()
            if cfg.useWebSocket { startWebSocket() }
        } else {
            client = nil
            quotes = []
            lastError = "config.json 에 API 키 입력 필요"
        }
        updateStatusTitle()
        buildMenu()
    }

    // REST 스냅샷: 기준가·이름·지수 갱신 (실시간 들어온 종목은 가격 유지)
    func refresh() {
        guard let client = client, let cfg = config else { return }
        Task {
            var result: [Quote] = []
            var firstError: String?
            for code in cfg.indices {
                do { result.append(try await client.fetchIndex(code: code)) }
                catch { if firstError == nil { firstError = "\(error)" } }
            }
            for code in cfg.stocks {
                do { result.append(try await client.fetchStock(code: code)) }
                catch { if firstError == nil { firstError = "\(error)" } }
            }
            let snapshot = result
            let err = firstError
            await MainActor.run {
                if !snapshot.isEmpty {
                    var merged: [Quote] = []
                    for q in snapshot {
                        if !q.isIndex, self.liveTick.contains(q.code),
                           let live = self.quotes.first(where: { $0.code == q.code && !$0.isIndex }) {
                            // 실시간 가격 유지, 기준가/이름만 REST로 갱신
                            merged.append(makeQuote(code: q.code, name: q.name,
                                                    price: live.price, base: q.base, isIndex: false))
                        } else {
                            merged.append(q)
                        }
                    }
                    if self.config?.useColor ?? true {
                        for q in merged {
                            if let old = self.prevPrices[q.code], old != q.price {
                                self.flash[q.code] = (q.price > old ? self.flashUp : self.flashDown,
                                                      Date().addingTimeInterval(self.flashDuration))
                            }
                        }
                    }
                    for q in merged { self.prevPrices[q.code] = q.price }
                    self.quotes = merged
                }
                self.lastError = snapshot.isEmpty ? err : nil
                self.lastUpdate = Date()
                self.updateStatusTitle()
                self.buildMenu()
                self.scheduleFlashRevert()
            }
        }
    }

    // 웹소켓 시작: 종목별 KRX 체결(S3_/K3_) 구독
    func startWebSocket() {
        guard let client = client, let cfg = config, cfg.useWebSocket else { return }
        Task {
            do {
                let tok = try await client.accessToken()
                await MainActor.run { self.connectWS(token: tok, cfg: cfg) }
            } catch {
                await MainActor.run { self.wsLog.append("토큰 오류: \(error)") }
            }
        }
    }

    func connectWS(token: String, cfg: Config) {
        let sock = LSWebSocket(token: token)
        sock.onRaw = { [weak self] text in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.wsLog.append(text)
                if self.wsLog.count > 30 { self.wsLog.removeFirst(self.wsLog.count - 30) }
            }
        }
        sock.onMessage = { [weak self] _, trKey, body in
            let price = firstDouble(body, ["price", "jisu", "pricejisu", "cur", "now"]) ?? 0
            DispatchQueue.main.async { self?.applyTick(code: trKey, price: price) }
        }
        var subscriptions: [(String, String)] = []
        for code in cfg.stocks {
            for tr in cfg.realtimeCodes {          // 기본 US3(통합): 정규장 KRX + 장후 NXT
                subscriptions.append((tr, code))
            }
        }
        sock.connect(subscriptions)
        ws = sock
    }

    // 실시간 체결가 적용
    func applyTick(code: String, price: Double) {
        guard price > 0, let i = quotes.firstIndex(where: { $0.code == code && !$0.isIndex }) else { return }
        let old = quotes[i].price
        let q = quotes[i]
        liveTick.insert(code)
        quotes[i] = makeQuote(code: q.code, name: q.name, price: price, base: q.base, isIndex: false)
        if (config?.useColor ?? true), old != price, old > 0 {
            flash[code] = (price > old ? flashUp : flashDown, Date().addingTimeInterval(flashDuration))
        }
        prevPrices[code] = price
        updateStatusTitle()
        scheduleFlashRevert()
    }

    // 메뉴바 타이틀
    func updateStatusTitle() {
        guard let button = statusItem.button else { return }
        let useColor = config?.useColor ?? true
        let showLabels = config?.showLabels ?? true
        let showChange = config?.showChange ?? true
        let attr = NSMutableAttributedString()

        if quotes.isEmpty {
            let msg = lastError.map { "⚠︎ \($0)" } ?? "주식 로딩…"
            attr.append(NSAttributedString(string: msg,
                attributes: [.font: barFont, .foregroundColor: NSColor.secondaryLabelColor]))
            button.attributedTitle = attr
            return
        }

        for (i, q) in quotes.enumerated() {
            if i > 0 { attr.append(NSAttributedString(string: "   ", attributes: [.font: barFont])) }
            let dec = q.isIndex ? 2 : 0
            let now = Date()

            // 종목명은 항상 기본색, 숫자만 변동 시 색상 변경
            let baseColor: NSColor = menuIsOpen ? .selectedMenuItemTextColor : .labelColor
            var valueColor = baseColor
            let valueFont = barFont
            if !menuIsOpen, useColor, let f = flash[q.code], now < f.until {
                valueColor = f.color
            }

            if showLabels {
                attr.append(NSAttributedString(string: "\(q.name) ",
                    attributes: [.font: barFont, .foregroundColor: baseColor]))
            }
            var valueStr = formatNumber(q.price, decimals: dec)
            if showChange { valueStr += " \(arrow(forSign: q.sign))\(formatNumber(q.diff, decimals: 2))%" }
            attr.append(NSAttributedString(string: valueStr,
                attributes: [.font: valueFont, .foregroundColor: valueColor]))
        }
        button.attributedTitle = attr
    }

    // 드롭다운 메뉴
    func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        if quotes.isEmpty, let err = lastError {
            let it = NSMenuItem(title: "⚠︎ \(err)", action: nil, keyEquivalent: "")
            it.isEnabled = false
            menu.addItem(it)
        } else {
            for q in quotes {
                let dec = q.isIndex ? 2 : 0
                let line = "\(q.name)   \(formatNumber(q.price, decimals: dec))   \(arrow(forSign: q.sign))\(formatNumber(q.diff, decimals: 2))%"
                let it = NSMenuItem(title: line, action: nil, keyEquivalent: "")
                it.isEnabled = false   // 비활성=호버 시 파란 하이라이트 없음 → 색 가독성 유지
                it.attributedTitle = NSAttributedString(string: line,
                    attributes: [.foregroundColor: NSColor.labelColor,
                                 .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)])
                menu.addItem(it)
            }
        }

        // 지수 값이 0이면 진단: 실제 응답 필드(key=value)를 드롭다운에 표시
        let indexZero = quotes.contains { $0.isIndex && $0.price == 0 }
        if indexZero, let blk = client?.lastIndexBlock, !blk.isEmpty {
            menu.addItem(.separator())
            let hdr = NSMenuItem(title: "▼ 지수 응답 필드 (진단)", action: nil, keyEquivalent: "")
            hdr.isEnabled = false
            menu.addItem(hdr)
            for (k, v) in blk.sorted(by: { $0.key < $1.key }) {
                let it = NSMenuItem(title: "\(k) = \(v)", action: nil, keyEquivalent: "")
                it.isEnabled = false
                it.attributedTitle = NSAttributedString(string: "\(k) = \(v)",
                    attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)])
                menu.addItem(it)
            }
        }

        menu.addItem(.separator())
        if let t = lastUpdate {
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
            let it = NSMenuItem(title: "마지막 갱신: \(f.string(from: t))", action: nil, keyEquivalent: "")
            it.isEnabled = false
            menu.addItem(it)
        }

        add(menu, "지금 새로고침", #selector(refreshNow), "r")
        add(menu, "종목 추가…", #selector(addStock), "n")

        // 삭제 서브메뉴
        let removeItem = NSMenuItem(title: "종목 삭제", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for code in (config?.stocks ?? []) {
            let nm = quotes.first(where: { $0.code == code && !$0.isIndex })?.name ?? code
            let it = NSMenuItem(title: "\(nm) (\(code))", action: #selector(removeEntry(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = "S:\(code)"; sub.addItem(it)
        }
        removeItem.submenu = sub
        removeItem.isEnabled = !sub.items.isEmpty
        menu.addItem(removeItem)

        menu.addItem(.separator())

        // 토글
        let labelToggle = NSMenuItem(title: "종목명 표시", action: #selector(toggleLabels), keyEquivalent: "")
        labelToggle.target = self
        labelToggle.state = (config?.showLabels ?? true) ? .on : .off
        menu.addItem(labelToggle)

        let changeToggle = NSMenuItem(title: "등락 표시", action: #selector(toggleChange), keyEquivalent: "")
        changeToggle.target = self
        changeToggle.state = (config?.showChange ?? true) ? .on : .off
        menu.addItem(changeToggle)

        let colorToggle = NSMenuItem(title: "변동 시 색상 깜빡임", action: #selector(toggleColor), keyEquivalent: "")
        colorToggle.target = self
        colorToggle.state = (config?.useColor ?? true) ? .on : .off
        menu.addItem(colorToggle)

        // 지수 표시 토글 (코스피/코스닥)
        let idxItem = NSMenuItem(title: "지수 표시", action: nil, keyEquivalent: "")
        let idxSub = NSMenu()
        for (nm, code) in [("코스피", "001"), ("코스닥", "301")] {
            let it = NSMenuItem(title: nm, action: #selector(toggleIndexItem(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = code
            it.state = (config?.indices.contains(code) ?? false) ? .on : .off
            idxSub.addItem(it)
        }
        idxItem.submenu = idxSub
        menu.addItem(idxItem)

        menu.addItem(.separator())
        add(menu, "지수 응답 보기(진단)", #selector(diagnoseIndex), "")
        add(menu, "주식 응답 보기(진단)", #selector(diagnoseStock), "")
        add(menu, "실시간 응답 보기(진단)", #selector(diagnoseRealtime), "")
        add(menu, "설정 파일 열기", #selector(openConfig), ",")
        if config?.debug ?? false {
            add(menu, "디버그 로그 보기", #selector(openDebug), "")
        }
        add(menu, "설정 다시 불러오기", #selector(reloadConfig), "")
        menu.addItem(.separator())
        add(menu, "종료", #selector(quit), "q")

        statusItem.menu = menu
    }

    @discardableResult
    func add(_ menu: NSMenu, _ title: String, _ sel: Selector, _ key: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        it.target = self
        menu.addItem(it)
        return it
    }

    // 깜빡임이 끝나는 시점에 기본색으로 되돌리기
    func scheduleFlashRevert() {
        flashTimer?.invalidate()
        guard let until = flash.values.map({ $0.until }).max(), until > Date() else { return }
        flashTimer = Timer.scheduledTimer(withTimeInterval: until.timeIntervalSinceNow + 0.05,
                                          repeats: false) { [weak self] _ in
            self?.updateStatusTitle()
        }
    }

    // MARK: 메뉴 델리게이트 (하이라이트 시 흰색)
    func menuWillOpen(_ menu: NSMenu) { menuIsOpen = true; updateStatusTitle() }
    func menuDidClose(_ menu: NSMenu) { menuIsOpen = false; updateStatusTitle() }

    // MARK: 액션
    @objc func refreshNow() { refresh() }
    @objc func reloadConfig() { reload() }
    @objc func quit() { NSApplication.shared.terminate(nil) }

    @objc func toggleLabels() {
        guard var cfg = config else { return }
        cfg.showLabels.toggle(); saveConfig(cfg); config = cfg
        updateStatusTitle(); buildMenu()
    }
    @objc func toggleChange() {
        guard var cfg = config else { return }
        cfg.showChange.toggle(); saveConfig(cfg); config = cfg
        updateStatusTitle(); buildMenu()
    }
    @objc func toggleColor() {
        guard var cfg = config else { return }
        cfg.useColor.toggle(); saveConfig(cfg); config = cfg
        updateStatusTitle(); buildMenu()
    }
    @objc func toggleIndexItem(_ sender: NSMenuItem) {
        guard var cfg = config, let code = sender.representedObject as? String else { return }
        if cfg.indices.contains(code) {
            cfg.indices.removeAll { $0 == code }
            quotes.removeAll { $0.isIndex && $0.code == code }
        } else {
            cfg.indices.append(code)
            cfg.indices.sort()
        }
        saveConfig(cfg); config = cfg
        updateStatusTitle(); buildMenu(); refresh()
    }

    @objc func diagnoseIndex() {
        let raw = client?.lastResponses["t1511"] ?? "(아직 응답이 없습니다 — '지금 새로고침' 후 다시 시도)"
        var pretty = raw
        if let d = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d),
           let pd = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
           let s = String(data: pd, encoding: .utf8) { pretty = s }
        showScrollable("지수(t1511) 원본 응답  (전체 선택 ⌘A → 복사 ⌘C 가능)", pretty)
    }

    @objc func diagnoseStock() {
        let raw = client?.lastResponses["t1102"] ?? "(아직 응답이 없습니다 — '지금 새로고침' 후 다시 시도)"
        var pretty = raw
        if let d = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d),
           let pd = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
           let s = String(data: pd, encoding: .utf8) { pretty = s }
        showScrollable("주식(t1102) 원본 응답  (전체 선택 ⌘A → 복사 ⌘C 가능)", pretty)
    }

    @objc func diagnoseRealtime() {
        let text = wsLog.isEmpty
            ? "(아직 실시간 메시지가 없습니다 — 정규장 시간에 잠시 후 다시 시도)"
            : wsLog.suffix(15).joined(separator: "\n\n")
        showScrollable("실시간(웹소켓) 원본 메시지  (⌘A → ⌘C 복사 가능)", text)
    }

    @objc func openConfig() { _ = loadConfig(); NSWorkspace.shared.open(configFileURL()) }
    @objc func openDebug() {
        var text = "# StockBar 디버그 로그 — \(Date())\n\n"
        for (tr, raw) in (client?.lastResponses ?? [:]) { text += "## \(tr)\n\(raw)\n\n" }
        try? text.write(to: debugLogURL(), atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(debugLogURL())
    }

    @objc func removeEntry(_ sender: NSMenuItem) {
        guard var cfg = config, let tag = sender.representedObject as? String else { return }
        let code = String(tag.dropFirst(2))
        if tag.hasPrefix("I:") { cfg.indices.removeAll { $0 == code } }
        else { cfg.stocks.removeAll { $0 == code } }
        saveConfig(cfg); config = cfg
        quotes.removeAll { $0.code == code }
        updateStatusTitle(); buildMenu(); refresh()
    }

    @objc func addStock() {
        let alert = NSAlert()
        alert.messageText = "종목 추가"
        alert.informativeText = "6자리 종목코드 또는 종목명을 입력하세요.\n예: 005930  또는  삼성전자"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "추가")
        alert.addButton(withTitle: "취소")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.makeFirstResponder(field)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let input = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }

        let digits = CharacterSet.decimalDigits
        if input.count == 6, input.unicodeScalars.allSatisfy({ digits.contains($0) }) {
            addCode(input, name: nil)
        } else {
            searchAndAdd(keyword: input)
        }
    }

    func addCode(_ code: String, name: String?) {
        guard var cfg = config else { return }
        if !cfg.stocks.contains(code) { cfg.stocks.append(code) }
        saveConfig(cfg); config = cfg
        buildMenu(); refresh()
    }

    func searchAndAdd(keyword: String) {
        guard let client = client else { return }
        Task {
            do {
                let matches = try await client.searchStocks(keyword)
                await MainActor.run {
                    if matches.isEmpty {
                        self.info("검색 결과 없음", "‘\(keyword)’ 에 해당하는 종목이 없습니다.\n6자리 종목코드로 추가해 보세요.")
                    } else if matches.count == 1 || matches[0].name == keyword {
                        let m = matches[0]
                        self.addCode(m.code, name: m.name)
                        self.info("추가됨", "\(m.name) (\(m.code))")
                    } else {
                        let list = matches.prefix(12).map { "\($0.name) (\($0.code))" }.joined(separator: "\n")
                        self.info("여러 종목이 검색됨", "원하는 종목의 6자리 코드로 다시 추가하세요:\n\n\(list)")
                    }
                }
            } catch {
                await MainActor.run {
                    self.info("검색 실패", "\(error)\n6자리 종목코드로 직접 추가해 주세요.")
                }
            }
        }
    }

    // 긴 내용을 스크롤+복사 가능한 창으로 표시
    func showScrollable(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 440, height: 380))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let tv = NSTextView(frame: scroll.bounds)
        tv.isEditable = false
        tv.isSelectable = true
        tv.string = text
        tv.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        scroll.documentView = tv
        a.accessoryView = scroll
        a.addButton(withTitle: "확인")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    func info(_ title: String, _ msg: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = msg
        a.addButton(withTitle: "확인")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

// MARK: - 진입점

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
