import Foundation
import Testing
@testable import Miko

struct AuthValidationTests {
    @Test func normalizesCredentials() {
        #expect(AuthValidation.normalizedEmail("  USER@Example.COM ") == "user@example.com")
        #expect(AuthValidation.normalizedUsername("  Miko  ") == "Miko")
    }

    @Test func rejectsInvalidEmail() {
        let error = AuthValidation.validate(
            mode: .signIn,
            username: "",
            email: "not-an-email",
            password: "password"
        )
        #expect(error != nil)
    }

    @Test func requiresUsernameOnlyForSignUp() {
        let signInError = AuthValidation.validate(
            mode: .signIn,
            username: "",
            email: "student@example.com",
            password: "password"
        )
        let signUpError = AuthValidation.validate(
            mode: .signUp,
            username: "",
            email: "student@example.com",
            password: "password"
        )
        #expect(signInError == nil)
        #expect(signUpError != nil)
    }

    @Test func requiresEightCharacterPassword() {
        let error = AuthValidation.validate(
            mode: .signUp,
            username: "Miko",
            email: "student@example.com",
            password: "1234567"
        )
        #expect(error != nil)
    }

    @Test func decodesDirectEmailConfirmationSignUpResponse() throws {
        let data = Data(
            #"{"id":"FD5E4842-8429-46A6-844B-93CB273AF297","email":"learner@example.org","user_metadata":{"username":"Miko"}}"#.utf8
        )

        let response = try JSONDecoder().decode(SupabaseAuthResponse.self, from: data)

        #expect(response.user.email == "learner@example.org")
        #expect(response.user.username == "Miko")
        #expect(response.session == nil)
    }

    @Test func decodesNestedPasswordSessionResponse() throws {
        let data = Data(
            #"{"access_token":"access","refresh_token":"refresh","expires_in":3600,"user":{"id":"FD5E4842-8429-46A6-844B-93CB273AF297","email":"learner@example.org","user_metadata":{"username":"Miko"}}}"#.utf8
        )

        let response = try JSONDecoder().decode(SupabaseAuthResponse.self, from: data)

        #expect(response.user.username == "Miko")
        #expect(response.session?.accessToken == "access")
        #expect(response.session?.refreshToken == "refresh")
    }

    @Test func loadsExplicitSupabaseConfiguration() throws {
        let configuration = try #require(SupabaseConfiguration.load(environment: [
            "SUPABASE_URL": "https://example.supabase.co",
            "SUPABASE_PUBLISHABLE_KEY": "demo-client-key"
        ]))

        #expect(configuration.projectURL.host == "example.supabase.co")
        #expect(configuration.publishableKey == "demo-client-key")
    }

    @Test func disablesCloudFeaturesWithoutSupabaseConfiguration() {
        #expect(SupabaseConfiguration.load(environment: [:]) == nil)
    }

    @Test func parsesEmailConfirmationCallback() throws {
        let url = try #require(URL(
            string: "miko://auth/callback#access_token=access%20token&refresh_token=refresh-token&expires_in=7200&type=signup"
        ))

        let tokens = try #require(AuthCallback.tokens(from: url))

        #expect(tokens.accessToken == "access token")
        #expect(tokens.refreshToken == "refresh-token")
        #expect(tokens.expiresIn == 7_200)
        #expect(tokens.type == "signup")
    }

    @Test func parsesPasswordRecoveryCallback() throws {
        let url = try #require(URL(
            string: "miko://auth/callback#access_token=access&refresh_token=refresh&type=recovery"
        ))

        #expect(AuthCallback.tokens(from: url)?.type == "recovery")
    }

    @Test func rejectsUnrelatedCallbackURL() {
        let url = URL(string: "https://localhost:3000/callback")!

        #expect(AuthCallback.matches(url) == false)
        #expect(AuthCallback.tokens(from: url) == nil)
    }

    @Test func decodesRateLimitErrorWhenHTTPCodeIsNumeric() throws {
        let data = Data(
            #"{"code":429,"error_code":"over_email_send_rate_limit","msg":"email rate limit exceeded"}"#.utf8
        )

        let response = try JSONDecoder().decode(SupabaseAuthClient.APIError.self, from: data)

        #expect(response.code == "429")
        #expect(response.errorCode == "over_email_send_rate_limit")
        #expect(response.msg == "email rate limit exceeded")
    }

    @Test func presentsRateLimitAsAHelpfulLocalizedError() {
        let error = SupabaseAuthClient.ClientError.server(
            code: "over_email_send_rate_limit",
            message: "email rate limit exceeded"
        )

        #expect(error.errorDescription == String(localized: "auth.error.rateLimit"))
    }
}
