import Foundation

protocol ProviderService {
    var providerID: ProviderID { get }
    func fetchSnapshot() async -> ProviderSnapshot
}
