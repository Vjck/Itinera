import SwiftUI

struct ExpensesView: View {
    @EnvironmentObject var store: AppStore
    let trip: Trip
    @State private var adding = false

    private var sorted: [Expense] {
        trip.expenses.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section { summary }
            let totals = ExpenseCategory.allCases.compactMap { category -> (ExpenseCategory, Double)? in
                let sum = trip.expenses.filter { $0.category == category }.reduce(0) { $0 + $1.amountEUR }
                return sum > 0 ? (category, sum) : nil
            }
            if !totals.isEmpty {
                Section("Per categoria") {
                    ForEach(totals, id: \.0) { category, sum in
                        HStack {
                            Label(category.title, systemImage: category.icon)
                            Spacer()
                            DualPrice(local: trip.toLocal(sum), trip: trip)
                        }
                    }
                }
            }
            Section("Spese") {
                if sorted.isEmpty {
                    Text("Ancora nessuna spesa. Tocca + per registrarne una.").foregroundStyle(.secondary)
                }
                ForEach(sorted) { expense in
                    HStack {
                        Image(systemName: expense.category.icon)
                            .foregroundStyle(Theme.accent)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(expense.title.isEmpty ? expense.category.title : expense.title)
                            Text(expense.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(money(expense.amountLocal, trip.currency)).font(.subheadline.weight(.semibold))
                            if !trip.usesEuro {
                                Text(money(expense.amountEUR, "EUR")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button("Elimina", role: .destructive) {
                            store.update(trip.id) { $0.expenses.removeAll { $0.id == expense.id } }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $adding) { ExpenseEditor(trip: trip) }
    }

    private var summary: some View {
        let spent = trip.spentEUR
        let budget = trip.budgetEUR
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speso").font(.caption).foregroundStyle(.secondary)
                    Text(money(spent, "EUR")).font(.title2.weight(.bold))
                    if !trip.usesEuro {
                        Text(money(trip.toLocal(spent), trip.currency)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if budget > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(spent > budget ? "Oltre il budget" : "Rimane")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(money(abs(budget - spent), "EUR"))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(spent > budget ? Color.red : Color.primary)
                        if !trip.usesEuro {
                            Text(money(trip.toLocal(abs(budget - spent)), trip.currency))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if budget > 0 {
                ProgressView(value: min(spent, budget), total: budget)
                    .tint(spent > budget ? Color.red : Theme.accent)
                Text("Budget: \(money(budget, "EUR"))").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Nessun budget impostato: tieni premuto il viaggio nell'elenco e scegli Modifica.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ExpenseEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    @State private var title = ""
    @State private var amount: Double?
    @State private var inEuro = false
    @State private var category: ExpenseCategory = .food
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Importo", value: $amount, format: .number)
                        .keyboardType(.decimalPad)
                        .font(.title2)
                    if !trip.usesEuro {
                        Picker("Valuta", selection: $inEuro) {
                            Text(trip.currency).tag(false)
                            Text("EUR").tag(true)
                        }
                        .pickerStyle(.segmented)
                        if let amount, amount > 0 {
                            Text("≈ " + (inEuro ? money(trip.toLocal(amount), trip.currency)
                                                 : money(trip.toEUR(amount), "EUR")))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    TextField("Descrizione", text: $title)
                    Picker("Categoria", selection: $category) {
                        ForEach(ExpenseCategory.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                    }
                    DatePicker("Quando", selection: $date)
                }
            }
            .navigationTitle("Nuova spesa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        guard let amount, amount > 0 else { return }
                        let euro = trip.usesEuro || inEuro
                        let expense = Expense(date: date, title: title.trimmingCharacters(in: .whitespaces),
                                              category: category,
                                              amountLocal: euro ? trip.toLocal(amount) : amount,
                                              amountEUR: euro ? amount : trip.toEUR(amount))
                        store.update(trip.id) { $0.expenses.append(expense) }
                        dismiss()
                    }
                    .disabled((amount ?? 0) <= 0)
                }
            }
        }
    }
}

struct ExchangeView: View {
    @EnvironmentObject var store: AppStore
    let trip: Trip
    @State private var local: Double?
    @State private var euro: Double?
    @State private var updating = false
    @State private var failed = false
    @FocusState private var focus: Field?

    enum Field { case local, euro }

    var body: some View {
        if trip.usesEuro {
            ContentUnavailableView("Viaggio in euro", systemImage: "eurosign.circle",
                                   description: Text("Qui non serve nessun cambio."))
        } else {
            Form {
                Section("Convertitore") {
                    HStack {
                        Text(trip.currency).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                        TextField("0", value: $local, format: .number)
                            .keyboardType(.decimalPad)
                            .focused($focus, equals: .local)
                            .font(.title2)
                    }
                    HStack {
                        Text("EUR").foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                        TextField("0", value: $euro, format: .number)
                            .keyboardType(.decimalPad)
                            .focused($focus, equals: .euro)
                            .font(.title2)
                    }
                }
                Section {
                    HStack {
                        Text("1 € =")
                        Spacer()
                        TextField("Cambio", value: rateBinding, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(trip.currency).foregroundStyle(.secondary)
                    }
                    Button {
                        updating = true
                        failed = false
                        Task {
                            failed = !(await store.refreshRate(trip.id))
                            updating = false
                        }
                    } label: {
                        HStack {
                            Text("Aggiorna cambio")
                            if updating { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(updating)
                } header: {
                    Text("Cambio")
                } footer: {
                    if failed {
                        Text("Aggiornamento non riuscito: controlla la connessione. Resta valido l'ultimo cambio salvato.")
                    } else if let date = trip.rateDate {
                        Text("Cambio di riferimento BCE del \(date). Banche e sportelli applicano di solito un cambio meno favorevole.")
                    } else {
                        Text("Cambio indicativo, non ancora aggiornato da internet.")
                    }
                }
                Section("A colpo d'occhio") {
                    ForEach(quickAmounts, id: \.self) { value in
                        HStack {
                            Text(money(value, trip.currency))
                            Spacer()
                            Text(money(trip.toEUR(value), "EUR")).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onChange(of: local) { _, value in
                if focus == .local { euro = value.map { rounded(trip.toEUR($0)) } }
            }
            .onChange(of: euro) { _, value in
                if focus == .euro { local = value.map { rounded(trip.toLocal($0)) } }
            }
            .onChange(of: trip.rate) { _, _ in
                if let local { euro = rounded(trip.toEUR(local)) }
            }
        }
    }

    private var rateBinding: Binding<Double?> {
        Binding(
            get: { trip.rate },
            set: { value in
                guard let value, value > 0 else { return }
                store.update(trip.id) {
                    $0.rate = value
                    $0.rateDate = nil
                }
            }
        )
    }

    /// Round amounts sized to the currency: about 5, 10, 20, 50 and 100 euro.
    private var quickAmounts: [Double] {
        let magnitude = pow(10, (log10(max(trip.rate, 0.0001))).rounded())
        return [5, 10, 20, 50, 100].map { $0 * magnitude }
    }

    private func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
