//
//  InvoicesView.swift
//  Construction Estimate
//
//

import SwiftUI

struct InvoicesView: View {

    @State private var selectedTab: String
    @State private var store = InvoiceStore.shared
    @State private var editingInvoice: Invoice?

    let filterTabs = ["Draft", "Scheduled", "Sent", "Paid"]

    init(initialTab: String = "Draft") {
        _selectedTab = State(initialValue: initialTab)
    }

    private var filteredInvoices: [Invoice] {
        store.invoices(forStatus: selectedTab)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Icons Row
            TopNavBar()
            
            // MARK: - Title
            HStack {
                Text("Invoices")
                    .font(.system(size: 32, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            
            // MARK: - Filter Tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filterTabs, id: \.self) { tab in
                        FilterTabButton(
                            title: tab,
                            count: store.invoices(forStatus: tab).count,
                            isSelected: selectedTab == tab
                        ) {
                            selectedTab = tab
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 16)
            
            // MARK: - Content
            ScrollView {
                if filteredInvoices.isEmpty {
                    VStack(spacing: 16) {
                        Spacer().frame(height: 60)

                        Text("You have no \(selectedTab.lowercased()) invoices.")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AppGray.ink)

                        Text("Open a project to create an invoice so every invoice stays connected to one job.")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(AppGray.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 60)
                            .padding(.bottom, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 120)
                } else {
                    VStack(spacing: 12) {
                        ForEach(filteredInvoices) { invoice in
                            HapticButton {
                                editingInvoice = invoice
                            } label: {
                                InvoiceSummaryCard(invoice: invoice)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 5)
                            }
                            .buttonStyle(PlainButtonStyle())
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 120)
                }
            }
        }
        .task {
            await store.refresh()
        }
        .sheet(item: $editingInvoice) { invoice in
            NavigationStack {
                InvoiceDetailView(invoice: invoice) { savedInvoice in
                    store.update(savedInvoice)
                }
            }
        }
    }
}

#Preview {
    InvoicesView()
}
