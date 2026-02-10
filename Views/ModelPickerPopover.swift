import SwiftUI

struct ModelPickerPopover: View {
    let models: [LLMModel]
    @Binding var selectedModelReference: String
    @Binding var searchText: String
    @Binding var isPresented: Bool

    @Environment(\.appTheme) private var theme

    private var filteredModels: [LLMModel] {
        if searchText.isEmpty { return models }
        return models.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.modelID.localizedCaseInsensitiveContains(searchText) ||
            $0.provider.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            theme.divider.frame(height: 1)
            modelList
        }
        .frame(width: 320, height: 400)
        .background(theme.surfaceBackground)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.textSecondary)
                .font(.system(size: 12))
            TextField("Search models...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(theme.textPrimary)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.textSecondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var modelList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if filteredModels.isEmpty {
                    Text("No models found")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                        .padding(12)
                } else {
                    ForEach(AIProvider.allCases) { provider in
                        providerSection(provider)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func providerSection(_ provider: AIProvider) -> some View {
        let providerModels = filteredModels.filter { $0.provider == provider }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        if !providerModels.isEmpty {
            HStack(spacing: 6) {
                ProviderIcon(slug: provider.iconSlug, size: 14)
                    .foregroundStyle(theme.textSecondary)
                Text(provider.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            ForEach(providerModels) { model in
                modelRow(model)
            }
        }
    }

    private func modelRow(_ model: LLMModel) -> some View {
        let isSelected = model.reference == selectedModelReference
        return Button {
            selectedModelReference = model.reference
            isPresented = false
            searchText = ""
        } label: {
            HStack(spacing: 8) {
                if let slug = modelIconSlug(for: model.modelID) {
                    ProviderIcon(slug: slug, size: 14)
                        .foregroundStyle(theme.textSecondary)
                }
                Text(model.displayName)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(theme.accent)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isSelected ? theme.selectionBackground : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }
}
