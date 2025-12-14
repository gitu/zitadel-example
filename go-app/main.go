package main

import (
	"context"
	"crypto/rand"
	"embed"
	_ "embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"html/template"
	"log/slog"
	"net/http"
	"net/url"
	"os"

	"github.com/zitadel/zitadel-go/v3/pkg/authentication"
	openid "github.com/zitadel/zitadel-go/v3/pkg/authentication/oidc"
	"github.com/zitadel/zitadel-go/v3/pkg/zitadel"
	"gopkg.in/yaml.v3"
)

var (
	// flags to be provided for running the example server
	key        = flag.String("key", "", "encryption key")
	port       = flag.String("port", "8091", "port to run the server on (default is 8089)")
	configFile = flag.String("config", "../secrets/direct-client.yaml", "path to the configuration file")
	//go:embed "templates/*.html"
	templates embed.FS
)

/*
This example demonstrates how to authenticate a user for your application with ZITADEL
using the provided authentication (AuthZ) middleware.

The main endpoint of the application is the /profile page, where some information about the
authenticated user will be displayed.

Additionally, the authentication handler will register some routes on the /auth path prefix,
to be able to redirect the user to the Login UI and back for authentication as well as for the sign-out.
*/

func main() {
	flag.Parse()

	config, err := LoadConfig(*configFile)
	if err != nil {
		slog.Error("error loading config", "error", err)
		os.Exit(1)
	}
	if config.ClientID == "" {
		slog.Error("client_id is required")
		os.Exit(1)
	}
	if *key == "" && config.Key == "" {
		config.Key = GenerateSecureToken(16)
	}
	if config.ZitadelPort == "" && config.ZitadelDomain == "" && config.Issuer != "" {
		zitadelURL, err := url.Parse(config.Issuer)
		if err != nil {
			slog.Error("error parsing issuer", "error", err)
			os.Exit(1)
		}
		config.ZitadelDomain = zitadelURL.Hostname()
		config.ZitadelPort = zitadelURL.Port()
	}

	ctx := context.Background()

	t, err := template.New("").ParseFS(templates, "templates/*.html")
	if err != nil {
		slog.Error("unable to parse template", "error", err)
		os.Exit(1)
	}

	// Initiate the authentication by providing a zitadel configuration and handler.
	// This example will use OIDC/OAuth2 PKCE Flow, therefore you will also need to initialize that with the generated client_id:
	authN, err := authentication.New(ctx, zitadel.New(config.ZitadelDomain, zitadel.WithInsecure(config.ZitadelPort)), config.Key,
		openid.DefaultAuthentication(config.ClientID, config.RedirectURL, config.Key),
	)
	if err != nil {
		slog.Error("zitadel sdk could not initialize", "error", err)
		os.Exit(1)
	}

	// Initialize the middleware by providing the sdk
	mw := authentication.Middleware(authN)

	router := http.NewServeMux()

	// Register the authentication handler on your desired path.
	// It will register the following handlers on it:
	// - /login (starts the authentication process to the Login UI)
	// - /callback (handles the redirect back from the Login UI)
	// - /logout (handles the logout process)
	router.Handle("/auth/", authN)
	// This endpoint is only accessible with a valid authentication. If there is none, it will directly redirect the user
	// to the Login UI for authentication. If successful (or already authenticated), the user will be presented the profile page.
	router.Handle("/profile", mw.RequireAuthentication()(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		// Using the [middleware.Context] function we can gather information about the authenticated user.
		// This example will just print a JSON representation of the UserInfo of the typed [*oidc.UserInfoContext].
		authCtx := mw.Context(req.Context())
		data, err := json.MarshalIndent(authCtx.UserInfo, "", " ")
		if err != nil {
			slog.Error("error marshalling profile response", "error", err)
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		err = t.ExecuteTemplate(w, "profile.html", string(data))
		if err != nil {
			slog.Error("error writing profile response", "error", err)
		}
	})))
	// This endpoint is accessible by anyone, but it will check if there already is a valid session (authentication).
	// If there is an active session, the information will be put into the context for later retrieval.
	router.Handle("/", mw.CheckAuthentication()(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		// In this case we check for an active session and directly redirect the user to the profile page.
		// You could certainly also use [middleware.Context] to get more information and use it in the home page.
		if authentication.IsAuthenticated(req.Context()) {
			http.Redirect(w, req, "/profile", http.StatusFound)
			return
		}
		err = t.ExecuteTemplate(w, "home.html", nil)
		if err != nil {
			slog.Error("error writing home page response", "error", err)
		}
	})))

	// start the server on the specified port (default http://localhost:8089)
	lis := fmt.Sprintf(":%s", *port)
	slog.Info("server listening, press ctrl+c to stop", "addr", "http://localhost"+lis)
	err = http.ListenAndServe(lis, router)
	if !errors.Is(err, http.ErrServerClosed) {
		slog.Error("server terminated", "error", err)
		os.Exit(1)
	}
}

type Config struct {
	ZitadelDomain string `yaml:"zitadel_domain"`
	ZitadelPort   string `yaml:"zitadel_port"`
	Issuer        string `yaml:"issuer"`
	Key           string `yaml:"key"`
	ClientID      string `yaml:"client_id"`
	RedirectURL   string `yaml:"redirect_url"`
}

func LoadConfig(s string) (Config, error) {
	yamlFile, err := os.ReadFile(s)
	if err != nil {
		return Config{}, err
	}
	var c Config
	err = yaml.Unmarshal(yamlFile, &c)
	if err != nil {
		return Config{}, err
	}
	return c, nil
}

func GenerateSecureToken(length int) string {
	b := make([]byte, length)
	if _, err := rand.Read(b); err != nil {
		return ""
	}
	return hex.EncodeToString(b)
}
