import Foundation

class FeedbackNetworkService {
    static let shared = FeedbackNetworkService()

    private init() {}

    func submitFeedback(_ message: String, completion: @escaping (Result<String, Error>) -> Void) {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedMessage.isEmpty else {
            completion(.failure(FeedbackError.emptyMessage))
            return
        }

        var components = URLComponents(string: "https://notifier.coffeedevs.com/api/events")
        components?.queryItems = [
            URLQueryItem(name: "project", value: "json_assistant"),
            URLQueryItem(name: "message", value: trimmedMessage),
            URLQueryItem(name: "status", value: "success"),
            URLQueryItem(name: "event_type", value: "Feedback")
        ]

        guard let url = components?.url else {
            completion(.failure(FeedbackError.invalidEndpoint))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if let httpResponse = response as? HTTPURLResponse,
               (200..<300).contains(httpResponse.statusCode) {
                completion(.success("Feedback sent successfully."))
            } else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                if statusCode >= 0 {
                    let error = FeedbackError.serverError(statusCode)
                    completion(.failure(error))
                } else {
                    completion(.failure(FeedbackError.connectionError))
                }
            }
        }.resume()
    }

    func diagnoseFeedbackError(_ error: Error) -> String {
        let nsError = error as NSError

        // Check if it's a URLError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return "No internet connection. Please check your network."
            case NSURLErrorNetworkConnectionLost:
                return "Network connection lost. Please try again."
            case NSURLErrorDNSLookupFailed:
                return "Unable to reach the feedback server (DNS lookup failed)."
            case NSURLErrorCannotFindHost:
                return "Unable to reach the feedback server (host not found)."
            case NSURLErrorCannotConnectToHost:
                return "Unable to connect to the feedback server. Please check your connection."
            case NSURLErrorTimedOut:
                return "Request timed out. Please check your connection and try again."
            case NSURLErrorSecureConnectionFailed:
                return "Secure connection failed. Your network may be blocking the request."
            case NSURLErrorServerCertificateUntrusted:
                return "Server certificate error. Please report this issue."
            default:
                return "Network error (\(nsError.code)): \(error.localizedDescription)"
            }
        }

        if let feedbackError = error as? FeedbackError {
            return feedbackError.errorDescription ?? "Unknown error"
        }

        return "Failed to submit: \(error.localizedDescription)"
    }
}

enum FeedbackError: LocalizedError {
    case emptyMessage
    case invalidEndpoint
    case serverError(Int)
    case connectionError

    var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return "Feedback cannot be empty."
        case .invalidEndpoint:
            return "Invalid feedback endpoint."
        case .serverError(let code):
            return "Server error (\(code)). Please try again later."
        case .connectionError:
            return "Unable to send feedback. Please check your connection."
        }
    }
}
