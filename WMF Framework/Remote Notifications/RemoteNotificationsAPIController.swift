import CocoaLumberjackSwift

public class RemoteNotificationsAPIController: Fetcher {
    // MARK: NotificationsAPI constants

    private struct NotificationsAPI {
        static let components: URLComponents = {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "www.mediawiki.org"
            components.path = "/w/api.php"
            return components
        }()
    }

    // MARK: Decodable: NotificationsResult

    struct ResultError: Decodable {
        let code, info: String?
    }

    public struct NotificationsResult: Decodable {
        
        struct Query: Decodable {
            
            struct Notifications: Decodable {
                let list: [Notification]
            }
            
            let notifications: Notifications?
        }
        
        let error: ResultError?
        let query: Query?
        
        public struct Notification: Decodable, Hashable {
            
            struct Timestamp: Decodable, Hashable {
                let utciso8601: String
                let utcunix: String
                
                enum CodingKeys: String, CodingKey {
                    case utciso8601
                    case utcunix
                }
                
                init(from decoder: Decoder) throws {
                    let values = try decoder.container(keyedBy: CodingKeys.self)
                    utciso8601 = try values.decode(String.self, forKey: .utciso8601)
                    do {
                        utcunix = String(try values.decode(Int.self, forKey: .utcunix))
                    } catch {
                        utcunix = try values.decode(String.self, forKey: .utcunix)
                    }
                }
            }
            struct Agent: Decodable, Hashable {
                let id: String?
                let name: String?
                
                enum CodingKeys: String, CodingKey {
                    case id
                    case name
                }
                
                init(from decoder: Decoder) throws {
                    let values = try decoder.container(keyedBy: CodingKeys.self)
                    name = try values.decode(String.self, forKey: .name)
                    do {
                        id = String(try values.decode(Int.self, forKey: .id))
                    } catch {
                        id = try values.decode(String.self, forKey: .id)
                    }
                }
            }
            struct Title: Decodable, Hashable {
                let full: String?
                let namespace: String?
                let namespaceKey: Int?
                let text: String?
                
                enum CodingKeys: String, CodingKey {
                    case full
                    case namespace
                    case namespaceKey = "namespace-key"
                    case text
                }
            }
            
            struct Message: Decodable, Hashable {
                let header: String?
                let body: String?
                let links: RemoteNotificationLinks?
            }
            
            let wiki: String
            let id: String
            let type: String
            let category: String
            let section: String
            let timestamp: Timestamp
            let title: Title?
            let agent: Agent?
            let readString: String?
            let message: Message?
            
            var key: String {
                return "\(wiki)-\(id)"
            }

            enum CodingKeys: String, CodingKey {
                case wiki
                case id
                case type
                case category
                case section
                case timestamp
                case title = "title"
                case agent
                case readString = "read"
                case message = "*"
            }

            public init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                wiki = try values.decode(String.self, forKey: .wiki)
                do {
                    id = String(try values.decode(Int.self, forKey: .id))
                } catch {
                    id = try values.decode(String.self, forKey: .id)
                }
                type = try values.decode(String.self, forKey: .type)
                category = try values.decode(String.self, forKey: .category)
                section = try values.decode(String.self, forKey: .section)
                timestamp = try values.decode(Timestamp.self, forKey: .timestamp)
                title = try? values.decode(Title.self, forKey: .title)
                agent = try? values.decode(Agent.self, forKey: .agent)
                readString = try? values.decode(String.self, forKey: .readString)
                message = try? values.decode(Message.self, forKey: .message)
            }
        }
    }

    // MARK: Decodable: MarkReadResult

    struct MarkReadResult: Decodable {
        let query: Query?
        let error: ResultError?

        var succeeded: Bool {
            return query?.markAsRead?.result == .success
        }

        struct Query: Decodable {
            let markAsRead: MarkedAsRead?

            enum CodingKeys: String, CodingKey {
                case markAsRead = "echomarkread"
            }
        }
        struct MarkedAsRead: Decodable {
            let result: Result?
        }
        enum Result: String, Decodable {
            case success
        }
    }

    enum MarkReadError: LocalizedError {
        case noResult
        case unknown
        case multiple([Error])
    }

    private func notifications(from result: NotificationsResult?) -> Set<NotificationsResult.Notification>? {
        guard let result = result else {
            return nil
        }
        guard let list = result.query?.notifications?.list else {
            return nil
        }
        return Set(list)
    }
    
    func getUnreadPushNotifications(from languageCode: String, completion:  @escaping (NotificationsResult.Query.Notifications?, Error?) -> Void) {
        let completion: (NotificationsResult?, URLResponse?, Error?) -> Void = { result, _, error in
            guard error == nil else {
                completion(nil, error)
                return
            }
            completion(result?.query?.notifications, result?.error)
        }
        
        request(languageCode: languageCode, queryParameters: Query.notifications(limit: .max, filter: .unread, notifierType: .push), completion: completion)
    }
    
    func getAllNotifications(from languageCode: String, completion: @escaping (NotificationsResult.Query.Notifications?, Error?) -> Void) {
        let completion: (NotificationsResult?, URLResponse?, Error?) -> Void = { result, _, error in
            guard error == nil else {
                completion(nil, error)
                return
            }
            completion(result?.query?.notifications, result?.error)
        }
        
        request(languageCode: languageCode, queryParameters: Query.notifications(from: [languageCode], limit: .max, filter: .none, notifierType: .web), completion: completion)
    }

    public func markAsRead(_ notifications: Set<RemoteNotification>, completion: @escaping (Error?) -> Void) {
        let maxNumberOfNotificationsPerRequest = 50
        let notifications = Array(notifications)
        let split = notifications.chunked(into: maxNumberOfNotificationsPerRequest)

        split.asyncCompactMap({ (notifications, completion: @escaping (Error?) -> Void) in
            request(languageCode: nil, queryParameters: Query.markAsRead(notifications: notifications), method: .post) { (result: MarkReadResult?, _, error) in
                if let error = error {
                    completion(error)
                    return
                }
                guard let result = result else {
                    assertionFailure("Expected result; make sure MarkReadResult maps the expected result correctly")
                    completion(MarkReadError.noResult)
                    return
                }
                if let error = result.error {
                    completion(error)
                    return
                }
                if !result.succeeded {
                    completion(MarkReadError.unknown)
                    return
                }
                completion(nil)
            }
        }) { (errors) in
            if errors.isEmpty {
                completion(nil)
            } else {
                DDLogError("\(errors.count) of \(split.count) mark as read requests failed")
                completion(MarkReadError.multiple(errors))
            }
        }
    }

    private func request<T: Decodable>(languageCode: String?, queryParameters: Query.Parameters?, method: Session.Request.Method = .get, completion: @escaping (T?, URLResponse?, Error?) -> Void) {
        
        let url: URL?
        if let languageCode = languageCode {
            if languageCode == "wikidata" {
                url = configuration.wikidataAPIURLComponents(with: queryParameters).url
            } else if languageCode == "commons" {
                url = configuration.commonsAPIURLComponents(with: queryParameters).url
            } else {
                url = configuration.mediaWikiAPIURLForLanguageCode(languageCode, with: queryParameters).url
            }
        } else {
            var components = NotificationsAPI.components
            components.replacePercentEncodedQueryWithQueryParameters(queryParameters)
            url = components.url
        }
        
        guard let url = url else {
            completion(nil, nil, RequestError.invalidParameters)
            return
        }
        
        if method == .get {
            session.jsonDecodableTask(with: url, method: .get, completionHandler: completion)
        } else {
            requestMediaWikiAPIAuthToken(for:url, type: .csrf) { (result) in
                switch result {
                case .failure(let error):
                    completion(nil, nil, error)
                case .success(let token):
                    self.session.jsonDecodableTask(with: url, method: method, bodyParameters: ["token": token.value], bodyEncoding: .form, completionHandler: completion)
                }
            }
        }
    }

    // MARK: Query parameters

    private struct Query {
        typealias Parameters = [String: String]

        enum Limit {
            case max
            case numeric(Int)

            var value: String {
                switch self {
                case .max:
                    return "max"
                case .numeric(let number):
                    return "\(number)"
                }
            }
        }

        enum Filter: String {
            case read = "read"
            case unread = "!read"
            case none = "read|!read"
        }
        
        enum NotifierType: String {
            case web
            case push
            case email
        }

        static func notifications(from subdomains: [String] = [], limit: Limit = .max, filter: Filter = .none, notifierType: NotifierType?) -> Parameters {
            var dictionary = ["action": "query",
                    "format": "json",
                    "formatversion": "2",
                    "notformat": "model",
                    "meta": "notifications",
                    "notlimit": limit.value,
                    "notfilter": filter.rawValue]
            
            if let notifierType = notifierType {
                dictionary["notnotifiertype"] = notifierType.rawValue
            }

            if subdomains.isEmpty {
                dictionary["notwikis"] = "*"
            } else {
                let wikis = subdomains.compactMap { $0.replacingOccurrences(of: "-", with: "_").appending("wiki") }
                dictionary["notwikis"] = wikis.joined(separator: "|")
            }
            
            return dictionary
        }

        static func markAsRead(notifications: [RemoteNotification]) -> Parameters? {
            let IDs = notifications.compactMap { $0.id }
            let wikis = notifications.compactMap { $0.wiki }
            return ["action": "echomarkread",
                    "format": "json",
                    "wikis": wikis.joined(separator: "|"),
                    "list":  IDs.joined(separator: "|")]
        }
    }
}

extension RemoteNotificationsAPIController.ResultError: LocalizedError {
    var errorDescription: String? {
        return info
    }
}

extension RemoteNotificationsAPIController {
    func isAuthenticatedForCookieDomain(_ cookieDomain: String) -> Bool {
        return session.hasValidCentralAuthCookies(for: cookieDomain)
    }
}
