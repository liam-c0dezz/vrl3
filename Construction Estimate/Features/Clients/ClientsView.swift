//
//  ClientsView.swift
//  Construction Estimate
//

import SwiftUI

struct ClientsView: View {
    @State private var store = ClientStore.shared
    @State private var showNewClient = false
    @State private var editingClient: Client?

    var body: some View {
        VStack(spacing: 0) {
            TopNavBar(onNewTapped: { showNewClient = true })

            HStack {
                Text(L("Clients"))
                    .font(.system(size: 32, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(store.clients) { client in
                        HapticButton {
                            editingClient = client
                        } label: {
                            ClientRow(client: client)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
        }
        .sheet(isPresented: $showNewClient) {
            NewClientSheet(onSave: { client in
                store.add(client)
                showNewClient = false
            })
            .presentationDetents([.large])
        }
        .sheet(item: $editingClient) { client in
            NewClientSheet(client: client, onSave: { updatedClient in
                store.update(updatedClient)
                editingClient = nil
            }, onDelete: {
                store.delete(client.id)
                editingClient = nil
            })
            .presentationDetents([.large])
        }
        .task {
            await store.refresh()
        }
    }
}

// MARK: - Client Row
struct ClientRow: View {
    let client: Client

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppGray.pill)
                    .frame(width: 44, height: 44)
                Text(client.initials)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppGray.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(client.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                if !client.company.isEmpty {
                    Text(client.company)
                        .font(.system(size: 13))
                        .foregroundColor(AppGray.secondary)
                } else if !client.phone.isEmpty {
                    Text(client.phone)
                        .font(.system(size: 13))
                        .foregroundColor(AppGray.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppGray.muted)
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

// MARK: - New Client Sheet
struct NewClientSheet: View {
    let client: Client?
    var onSave: (Client) -> Void
    var onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var company: String
    @State private var email: String
    @State private var phone: String
    @State private var address: String
    @State private var referralSource: String
    @State private var showingDeleteOptions = false

    init(
        client: Client? = nil,
        onSave: @escaping (Client) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.client = client
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: client?.name ?? "")
        _company = State(initialValue: client?.company ?? "")
        _email = State(initialValue: client?.email ?? "")
        _phone = State(initialValue: client?.phone ?? "")
        _address = State(initialValue: client?.address ?? "")
        _referralSource = State(initialValue: client?.referralSource ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                navigationHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        card(L("Full name")) {
                            TextField(L("Name"), text: $name)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(AppGray.secondary)
                        }
                        card(L("Company")) {
                            TextField(L("Company name"), text: $company)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(AppGray.secondary)
                        }
                        card(L("Email")) {
                            TextField(L("Email address"), text: $email)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(AppGray.secondary)
                        }
                        card(L("Phone")) {
                            TextField(L("Phone number"), text: $phone)
                                .keyboardType(.phonePad)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(AppGray.secondary)
                        }
                        card(L("Address")) {
                            TextField(L("Address"), text: $address)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(AppGray.secondary)
                        }
                        card(L("Referral source")) {
                            TextField(L("Referral source"), text: $referralSource)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(AppGray.secondary)
                        }

                        HapticButton(action: saveClient) {
                            Text(L("Save"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(AppGray.ink)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                    }
                    .padding(20)
                }
            }
            .background(Color.white.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog(L("Client Options"), isPresented: $showingDeleteOptions) {
                HapticButton("Delete Client", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                HapticButton("Cancel", role: .cancel) {}
            }
        }
    }

    private var navigationHeader: some View {
        ZStack {
            Text(client == nil ? L("New Client") : L("Edit Client"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AppGray.ink)

            HStack {
                HapticButton { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(AppGray.ink)
                        .frame(width: 44, height: 44)
                        .glassEffect(.clear.tint(Color.white.opacity(0.72)), in: Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                HapticButton { showingDeleteOptions = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppGray.ink)
                        .rotationEffect(.degrees(90))
                        .frame(width: 44, height: 44)
                        .glassEffect(.clear.tint(Color.white.opacity(0.72)), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .background(Color.white)
    }

    private func saveClient() {
        let savedClient = Client(
            id: client?.id ?? UUID(),
            organizationId: client?.organizationId,
            name: name.isEmpty ? L("Unnamed Client") : name,
            company: company,
            email: email,
            phone: phone,
            address: address,
            referralSource: referralSource
        )
        onSave(savedClient)
    }

    // Titled card with a white rounded field + stroke (matches the form/edit popups).
    @ViewBuilder
    private func card<Content: View>(
        _ title: String,
        @ViewBuilder _ content: () -> Content,
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L(title))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(AppGray.textDark)
            content()
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(AppGray.border, lineWidth: 1)
                )
        }
    }
}

struct NewClientField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(AppGray.secondary)
                .frame(width: 20)
            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .keyboardType(keyboard)
        }
        .padding(14)
        .background(AppGray.bgFaint)
        .cornerRadius(12)
    }
}

// MARK: - Client Picker Sheet (used from ProjectDetailView)
struct ClientPickerSheet: View {
    @State private var store = ClientStore.shared
    @State private var showNewClient = false
    var onSelect: (Client) -> Void
    @Environment(\.dismiss) private var dismiss

    private let brandBlue = AppBrand.accent

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(AppGray.border)
                .frame(width: 40, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 20)

            HStack {
                Text(L("Select Client"))
                    .font(.system(size: 20, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 0) {
                    // Existing clients
                    ForEach(store.clients) { client in
                        HapticButton(action: {
                            onSelect(client)
                            dismiss()
                        }) {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(AppGray.pill)
                                        .frame(width: 44, height: 44)
                                    Text(client.initials)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(AppGray.secondary)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(client.name)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.black)
                                    if !client.company.isEmpty {
                                        Text(client.company)
                                            .font(.system(size: 13))
                                            .foregroundColor(AppGray.secondary)
                                    } else if !client.phone.isEmpty {
                                        Text(client.phone)
                                            .font(.system(size: 13))
                                            .foregroundColor(AppGray.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13))
                                    .foregroundColor(AppGray.borderStrong)
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                        }
                        Divider().padding(.leading, 82)
                    }

                    // New Client row
                    HapticButton(action: { showNewClient = true }) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(brandBlue.opacity(0.1))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "person.fill.badge.plus")
                                    .font(.system(size: 18))
                                    .foregroundColor(brandBlue)
                            }
                            Text(L("New Client"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(brandBlue)
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                    }
                }
            }
        }
        .sheet(isPresented: $showNewClient) {
            NewClientSheet(onSave: { client in
                store.add(client)
                showNewClient = false
                onSelect(client)
                dismiss()
            })
            .presentationDetents([.large])
        }
        .task {
            await store.refresh()
        }
    }
}

#Preview {
    ClientsView()
}
