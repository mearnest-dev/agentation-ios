import SwiftUI
import Agentation

/// SwiftUI screen with a few things worth annotating.
struct CheckoutView: View {
    @State private var shipping = 0
    @State private var giftNote = ""

    private struct Item {
        let name: String
        let price: Double
    }

    private let items = [
        Item(name: "Ceramic mug", price: 18),
        Item(name: "Pour-over kettle", price: 54),
        Item(name: "Coffee beans, 1kg", price: 32),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your cart")
                        .font(.title2.bold())
                    ForEach(items, id: \.name) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Text(item.price, format: .currency(code: "USD"))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("cart.item.\(item.name)")
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .agentationTag("CartItemsCard")
                .agentationSource()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Shipping")
                        .font(.headline)
                    Picker("Shipping", selection: $shipping) {
                        Text("Standard (3–5 days)").tag(0)
                        Text("Express (1–2 days)").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("checkout.shippingPicker")

                    TextField("Gift note (optional)", text: $giftNote)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("checkout.giftNote")
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .agentationTag("ShippingOptions")
                .agentationSource()

                PaymentSummary(total: total)
            }
            .padding()
        }
        .navigationTitle("Checkout")
    }

    private var total: Double {
        items.map(\.price).reduce(0, +) + (shipping == 1 ? 12 : 0)
    }
}

struct PaymentSummary: View {
    let total: Double

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Total")
                Spacer()
                Text(total, format: .currency(code: "USD"))
                    .bold()
            }
            Button {
            } label: {
                Text("Pay \(total, format: .currency(code: "USD"))")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            // Deliberately smaller radius than the cards above: something to annotate.
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityIdentifier("checkout.payButton")
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .agentationTag("PaymentSummaryCard")
        .agentationSource()
    }
}
