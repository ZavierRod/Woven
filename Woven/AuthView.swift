import SwiftUI

// MARK: - Auth View (Login/SignUp Container)

struct AuthView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var showSignUp = false
    @State private var appeared = false
    
    var body: some View {
        ZStack {
            // Background
            WovenTheme.background.ignoresSafeArea()
            
            // Ambient glow
            Circle()
                .fill(WovenTheme.accent.opacity(0.08))
                .frame(width: 300, height: 300)
                .blur(radius: 100)
                .offset(y: -200)
            
            VStack(spacing: 0) {
                Spacer()
                
                // Logo
                VStack(spacing: WovenTheme.spacing16) {
                    // Woven loop glyph
                    ZStack {
                        Circle()
                            .stroke(WovenTheme.accent.opacity(0.3), lineWidth: 2)
                            .frame(width: 60, height: 60)
                        Circle()
                            .stroke(WovenTheme.accent.opacity(0.3), lineWidth: 2)
                            .frame(width: 60, height: 60)
                            .offset(x: 20)
                    }
                    .frame(width: 80, height: 60)
                    
                    Text("Woven")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(WovenTheme.textPrimary)
                }
                .padding(.bottom, WovenTheme.spacing32)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : -20)
                
                // Auth Card
                VStack(spacing: WovenTheme.spacing24) {
                    if showSignUp {
                        SignUpFormView(showSignUp: $showSignUp)
                    } else {
                        LoginFormView(showSignUp: $showSignUp)
                    }
                }
                .padding(WovenTheme.spacing24)
                .background(WovenTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusCard, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                .padding(.horizontal, WovenTheme.spacing20)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 30)
                
                Spacer()
                
                // Footer
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 12))
                        .foregroundColor(WovenTheme.accent.opacity(0.7))
                    Text("Your data is encrypted and secure")
                        .font(WovenTheme.caption())
                        .foregroundColor(WovenTheme.textTertiary)
                }
                .padding(.bottom, 40)
                .opacity(appeared ? 1 : 0)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }
}

// MARK: - Login Form

struct LoginFormView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Binding var showSignUp: Bool
    
    @State private var identifier = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?
    
    enum Field { case identifier, password }
    
    var body: some View {
        VStack(spacing: WovenTheme.spacing20) {
            // Header
            VStack(spacing: WovenTheme.spacing8) {
                Text("Welcome back")
                    .font(WovenTheme.title2())
                    .foregroundColor(WovenTheme.textPrimary)
                
                Text("Sign in to access your vaults")
                    .font(WovenTheme.subheadline())
                    .foregroundColor(WovenTheme.textSecondary)
            }
            
            // Fields
            VStack(spacing: WovenTheme.spacing12) {
                AuthTextField(
                    placeholder: "Email or username",
                    text: $identifier,
                    icon: "person",
                    keyboardType: .emailAddress,
                    autocapitalization: .never
                )
                .focused($focusedField, equals: .identifier)
                .submitLabel(.next)
                .onSubmit { focusedField = .password }
                
                AuthTextField(
                    placeholder: "Password",
                    text: $password,
                    icon: "lock",
                    isSecure: true
                )
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit { login() }
            }
            
            // Error message
            if let error = authManager.errorMessage {
                Text(error)
                    .font(WovenTheme.caption())
                    .foregroundColor(WovenTheme.error)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
            
            // Login Button
            Button {
                login()
            } label: {
                if authManager.isLoading {
                    ProgressView()
                        .tint(.black)
                } else {
                    Text("Sign In")
                }
            }
            .buttonStyle(WovenButtonStyle(isEnabled: isValid && !authManager.isLoading))
            .disabled(!isValid || authManager.isLoading)
            
            // Sign up link
            HStack(spacing: 4) {
                Text("Don't have an account?")
                    .foregroundColor(WovenTheme.textSecondary)
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        authManager.clearError()
                        showSignUp = true
                    }
                } label: {
                    Text("Sign Up")
                        .fontWeight(.semibold)
                        .foregroundColor(WovenTheme.accent)
                }
            }
            .font(WovenTheme.subheadline())
        }
    }
    
    private var isValid: Bool {
        !identifier.isEmpty && !password.isEmpty
    }
    
    private func login() {
        guard isValid else { return }
        focusedField = nil
        
        Task {
            await authManager.login(identifier: identifier, password: password)
        }
    }
}

// MARK: - Sign Up Form

struct SignUpFormView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Binding var showSignUp: Bool
    
    @State private var username = ""
    @State private var email = ""
    @State private var fullName = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @FocusState private var focusedField: Field?
    
    enum Field { case fullName, username, email, password, confirmPassword }
    
    var body: some View {
        VStack(spacing: WovenTheme.spacing20) {
            // Header
            VStack(spacing: WovenTheme.spacing8) {
                Text("Create account")
                    .font(WovenTheme.title2())
                    .foregroundColor(WovenTheme.textPrimary)
                
                Text("Start securing your memories")
                    .font(WovenTheme.subheadline())
                    .foregroundColor(WovenTheme.textSecondary)
            }
            
            // Fields
            VStack(spacing: WovenTheme.spacing12) {
                AuthTextField(
                    placeholder: "Full name (optional)",
                    text: $fullName,
                    icon: "person.text.rectangle"
                )
                .focused($focusedField, equals: .fullName)
                .submitLabel(.next)
                .onSubmit { focusedField = .username }
                
                AuthTextField(
                    placeholder: "Username",
                    text: $username,
                    icon: "at",
                    autocapitalization: .never
                )
                .focused($focusedField, equals: .username)
                .submitLabel(.next)
                .onSubmit { focusedField = .email }
                
                AuthTextField(
                    placeholder: "Email",
                    text: $email,
                    icon: "envelope",
                    keyboardType: .emailAddress,
                    autocapitalization: .never
                )
                .focused($focusedField, equals: .email)
                .submitLabel(.next)
                .onSubmit { focusedField = .password }
                
                AuthTextField(
                    placeholder: "Password (8+ characters)",
                    text: $password,
                    icon: "lock",
                    isSecure: true
                )
                .focused($focusedField, equals: .password)
                .submitLabel(.next)
                .onSubmit { focusedField = .confirmPassword }
                
                AuthTextField(
                    placeholder: "Confirm password",
                    text: $confirmPassword,
                    icon: "lock.fill",
                    isSecure: true
                )
                .focused($focusedField, equals: .confirmPassword)
                .submitLabel(.go)
                .onSubmit { signUp() }
            }
            
            // Validation errors
            if let validationError = validationError {
                Text(validationError)
                    .font(WovenTheme.caption())
                    .foregroundColor(WovenTheme.warning)
                    .multilineTextAlignment(.center)
            }
            
            // Server error
            if let error = authManager.errorMessage {
                Text(error)
                    .font(WovenTheme.caption())
                    .foregroundColor(WovenTheme.error)
                    .multilineTextAlignment(.center)
            }
            
            // Sign Up Button
            Button {
                signUp()
            } label: {
                if authManager.isLoading {
                    ProgressView()
                        .tint(.black)
                } else {
                    Text("Create Account")
                }
            }
            .buttonStyle(WovenButtonStyle(isEnabled: isValid && !authManager.isLoading))
            .disabled(!isValid || authManager.isLoading)
            
            // Login link
            HStack(spacing: 4) {
                Text("Already have an account?")
                    .foregroundColor(WovenTheme.textSecondary)
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        authManager.clearError()
                        showSignUp = false
                    }
                } label: {
                    Text("Sign In")
                        .fontWeight(.semibold)
                        .foregroundColor(WovenTheme.accent)
                }
            }
            .font(WovenTheme.subheadline())
        }
    }
    
    private var validationError: String? {
        if !username.isEmpty && username.count < 3 {
            return "Username must be at least 3 characters"
        }
        if !password.isEmpty && password.count < 8 {
            return "Password must be at least 8 characters"
        }
        if !confirmPassword.isEmpty && password != confirmPassword {
            return "Passwords don't match"
        }
        return nil
    }
    
    private var isValid: Bool {
        !username.isEmpty &&
        username.count >= 3 &&
        !email.isEmpty &&
        email.contains("@") &&
        !password.isEmpty &&
        password.count >= 8 &&
        password == confirmPassword &&
        validationError == nil
    }
    
    private func signUp() {
        guard isValid else { return }
        focusedField = nil
        
        Task {
            let name = fullName.isEmpty ? nil : fullName
            await authManager.signUp(
                username: username,
                email: email,
                password: password,
                fullName: name
            )
        }
    }
}

// MARK: - Auth Text Field

struct AuthTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String = ""
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    
    @State private var showPassword = false
    
    var body: some View {
        HStack(spacing: WovenTheme.spacing12) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(WovenTheme.textTertiary)
                    .frame(width: 20)
            }
            
            if isSecure && !showPassword {
                SecureField(placeholder, text: $text)
                    .textContentType(.password)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(autocapitalization)
                    .autocorrectionDisabled()
            }
            
            if isSecure {
                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.system(size: 14))
                        .foregroundColor(WovenTheme.textTertiary)
                }
            }
        }
        .font(WovenTheme.body())
        .foregroundColor(WovenTheme.textPrimary)
        .padding(WovenTheme.spacing16)
        .background(WovenTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusMedium, style: .continuous))
    }
}

// MARK: - Preview

#Preview {
    AuthView()
        .environmentObject(AuthenticationManager())
}

