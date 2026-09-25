import XCTest

final class BetterFishingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSmokeLaunchShowsSourceSelectorWithUIUnitDouble() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-double", "identifiedReliable"]
        app.launch()

        let sourceSelector = app.otherElements["scanner.sourceSelector"]
        XCTAssertTrue(sourceSelector.waitForExistence(timeout: 10), "El selector de fuente debe aparecer tras el arranque")
    }

    func testCameraFlowCapturesAndShowsIdentifiedSpecies() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-double", "identifiedReliable"]
        app.launch()

        let sourceSelector = app.otherElements["scanner.sourceSelector"]
        XCTAssertTrue(sourceSelector.waitForExistence(timeout: 10), "El selector de fuente debe aparecer tras el arranque")

        app.buttons["scanner.cameraSource"].tap()

        let cameraPreview = app.otherElements["scanner.cameraPreview"]
        XCTAssertTrue(cameraPreview.waitForExistence(timeout: 10), "La preview de cámara debe aparecer con el permiso concedido (stub)")

        app.buttons["scanner.cameraShutter"].tap()

        let identifying = app.otherElements["scanner.identifying"]
        XCTAssertTrue(identifying.waitForExistence(timeout: 10), "El estado de carga debe aparecer al identificar")

        let speciesName = app.staticTexts["scanner.speciesName"]
        XCTAssertTrue(speciesName.waitForExistence(timeout: 10), "El resultado debe mostrar el nombre de la especie")
        XCTAssertTrue(speciesName.label.contains("Largemouth Bass"), "La especie debe ser Largemouth Bass (reliableBass), obtenido: \(speciesName.label)")
    }

    func testGallerySelectionShowsLowConfidenceWarning() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-double", "identifiedLowConfidence"]
        app.launch()

        let sourceSelector = app.otherElements["scanner.sourceSelector"]
        XCTAssertTrue(sourceSelector.waitForExistence(timeout: 10), "El selector de fuente debe aparecer tras el arranque")

        app.buttons["scanner.gallerySource"].tap()

        let identifying = app.otherElements["scanner.identifying"]
        XCTAssertTrue(identifying.waitForExistence(timeout: 10), "El estado de carga debe aparecer al identificar la imagen de galería")

        let speciesName = app.staticTexts["scanner.speciesName"]
        XCTAssertTrue(speciesName.waitForExistence(timeout: 10), "El resultado debe mostrar el nombre de la especie")
        XCTAssertTrue(speciesName.label.contains("Bluegill"), "La especie debe ser Bluegill (lowConfidenceBluegill), obtenido: \(speciesName.label)")

        let warning = app.descendants(matching: .any)["scanner.lowConfidenceWarning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 10), "El aviso de fiabilidad debe aparecer con confianza baja")
    }

    func testNoMatchFlowShowsMessageAndRetryReturnsToSourceSelector() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-double", "noMatch"]
        app.launch()

        let sourceSelector = app.otherElements["scanner.sourceSelector"]
        XCTAssertTrue(sourceSelector.waitForExistence(timeout: 10), "El selector de fuente debe aparecer tras el arranque")

        app.buttons["scanner.gallerySource"].tap()

        let identifying = app.otherElements["scanner.identifying"]
        XCTAssertTrue(identifying.waitForExistence(timeout: 10), "El estado de carga debe aparecer al identificar la imagen de galería")

        let noMatch = app.descendants(matching: .any)["scanner.noMatch"]
        XCTAssertTrue(noMatch.waitForExistence(timeout: 10), "El aviso de no identificación debe aparecer cuando no hay coincidencia")

        let noMatchTitle = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "No se pudo identificar"))
        XCTAssertTrue(noMatchTitle.firstMatch.exists, "El aviso debe informar de que no se ha podido identificar la especie")

        app.buttons["scanner.retry"].tap()

        XCTAssertTrue(sourceSelector.waitForExistence(timeout: 10), "El reintento debe volver al selector de fuente para una nueva imagen")
        XCTAssertFalse(noMatch.exists, "El aviso de no identificación debe desaparecer tras el reintento")
    }

    func testSaveSuccessFlowConfirmsPrefilledDraftAndSaves() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-double", "saveSucceeds"]
        app.launch()

        let sourceSelector = app.otherElements["scanner.sourceSelector"]
        XCTAssertTrue(sourceSelector.waitForExistence(timeout: 10), "El selector de fuente debe aparecer tras el arranque")

        app.buttons["scanner.gallerySource"].tap()

        let identifying = app.otherElements["scanner.identifying"]
        XCTAssertTrue(identifying.waitForExistence(timeout: 10), "El estado de carga debe aparecer al identificar la imagen de galería")

        let speciesName = app.staticTexts["scanner.speciesName"]
        XCTAssertTrue(speciesName.waitForExistence(timeout: 10), "El resultado debe mostrar el nombre de la especie")
        XCTAssertTrue(speciesName.label.contains("Largemouth Bass"), "El identificador debe devolver Largemouth Bass (saveSucceeds), obtenido: \(speciesName.label)")

        let saveCatch = app.buttons["scanner.saveCatch"]
        XCTAssertTrue(saveCatch.waitForExistence(timeout: 5), "Con la especie identificada debe ofrecerse guardar la captura")
        saveCatch.tap()

        let confirmationAlert = app.alerts["Guardar la captura"]
        XCTAssertTrue(confirmationAlert.waitForExistence(timeout: 5), "Debe aparecer la confirmación de guardado con la especie pre-rellena")
        let confirmationPrefill = confirmationAlert.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "Largemouth Bass")
        )
        XCTAssertTrue(confirmationPrefill.firstMatch.exists, "La confirmación debe pre-rellenar la especie identificada")
        let confirmationScientific = confirmationAlert.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "Micropterus salmoides")
        )
        XCTAssertTrue(confirmationScientific.firstMatch.exists, "La confirmación debe pre-rellenar también el nombre científico")

        let saveConfirm = app.alerts["Guardar la captura"].buttons["scanner.saveConfirm"].firstMatch
        XCTAssertTrue(saveConfirm.exists, "La confirmación debe permitir guardar la captura")
        saveConfirm.tap()

        let savedSuccessAlert = app.alerts["Captura guardada"]
        XCTAssertTrue(savedSuccessAlert.waitForExistence(timeout: 10), "El guardado con éxito debe confirmar que la captura se ha guardado")
        XCTAssertFalse(app.buttons["scanner.saveRetry"].firstMatch.exists, "En el flujo de éxito no debe mostrarse error de guardado")

        app.alerts["Captura guardada"].buttons["scanner.saveSuccessContinue"].firstMatch.tap()

        XCTAssertTrue(sourceSelector.waitForExistence(timeout: 10), "Volver al inicio debe regresar al selector de fuente")
    }

    func testSaveFailureFlowShowsRetryAndRecoversOnRetry() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-double", "saveFails"]
        app.launch()

        let sourceSelector = app.otherElements["scanner.sourceSelector"]
        XCTAssertTrue(sourceSelector.waitForExistence(timeout: 10), "El selector de fuente debe aparecer tras el arranque")

        app.buttons["scanner.gallerySource"].tap()

        let identifying = app.otherElements["scanner.identifying"]
        XCTAssertTrue(identifying.waitForExistence(timeout: 10), "El estado de carga debe aparecer al identificar la imagen de galería")

        let speciesName = app.staticTexts["scanner.speciesName"]
        XCTAssertTrue(speciesName.waitForExistence(timeout: 10), "El resultado debe mostrar el nombre de la especie")

        let saveCatch = app.buttons["scanner.saveCatch"]
        XCTAssertTrue(saveCatch.waitForExistence(timeout: 5), "Con la especie identificada debe ofrecerse guardar la captura")
        saveCatch.tap()

        let confirmationAlert = app.alerts["Guardar la captura"]
        XCTAssertTrue(confirmationAlert.waitForExistence(timeout: 5), "Debe aparecer la confirmación de guardado pre-rellena")
        let confirmationPrefill = confirmationAlert.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "Largemouth Bass")
        )
        XCTAssertTrue(confirmationPrefill.firstMatch.exists, "La confirmación debe pre-rellenar la especie identificada")

        app.alerts["Guardar la captura"].buttons["scanner.saveConfirm"].firstMatch.tap()

        let retry = app.buttons["scanner.saveRetry"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 10), "Un fallo de guardado debe informar del fallo y ofrecer reintento")
        let failedAlert = app.alerts["No se pudo guardar la captura"]
        XCTAssertTrue(failedAlert.exists, "El aviso de fallo debe explicar que la especie se mantiene en pantalla")
        let failedMessage = failedAlert.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "La especie identificada se mantiene en pantalla")
        )
        XCTAssertTrue(failedMessage.firstMatch.exists, "El aviso de fallo debe indicar que la especie se mantiene en pantalla")

        retry.tap()

        let savedSuccessAlert = app.alerts["Captura guardada"]
        XCTAssertTrue(savedSuccessAlert.waitForExistence(timeout: 10), "El reintento tras el fallo debe conseguir guardar la captura")
        XCTAssertFalse(retry.exists, "Tras el reintento con éxito, el error de guardado debe desaparecer")
    }

    func testAccountTabShowsSessionFormWhenSignedOut() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-double", "accountSignedOut"]
        app.launch()

        let accountTab = app.tabBars.firstMatch.buttons["Cuenta"]
        XCTAssertTrue(accountTab.waitForExistence(timeout: 10), "La navegación principal debe ofrecer la pestaña Cuenta")
        accountTab.tap()

        XCTAssertTrue(app.textFields["account.email"].waitForExistence(timeout: 10), "Cuenta sin sesión debe mostrar el formulario de acceso")
        XCTAssertTrue(app.secureTextFields["account.password"].exists)
        XCTAssertTrue(app.buttons["account.submit"].exists)
    }

    func testAccountTabShowsProfileFavoritesAndSyncWhenSignedIn() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-double", "accountSignedIn"]
        app.launch()

        let accountTab = app.tabBars.firstMatch.buttons["Cuenta"]
        XCTAssertTrue(accountTab.waitForExistence(timeout: 10), "La navegación principal debe ofrecer la pestaña Cuenta")
        accountTab.tap()

        let displayName = app.textFields["account.displayName"]
        XCTAssertTrue(displayName.waitForExistence(timeout: 10), "Cuenta con sesión debe mostrar el perfil")
        XCTAssertEqual(displayName.value as? String, "Pescador de prueba")
        XCTAssertTrue(app.staticTexts["Embalse de Sau"].waitForExistence(timeout: 10), "La lista debe mostrar los favoritos del usuario")
        XCTAssertTrue(app.buttons["account.syncButton"].exists)
        XCTAssertTrue(app.buttons["account.signOut"].exists)

        app.buttons["account.syncButton"].tap()
        let syncResult = app.descendants(matching: .any)["account.syncResult"]
        XCTAssertTrue(syncResult.waitForExistence(timeout: 10), "La sincronización debe mostrar su resultado")
        XCTAssertTrue(syncResult.label.contains("Subidos 1"))
        XCTAssertTrue(syncResult.label.contains("Descargados 2"))
        XCTAssertTrue(syncResult.label.contains("Omitidos 3"))

        app.buttons["account.signOut"].tap()
        XCTAssertTrue(app.textFields["account.email"].waitForExistence(timeout: 10), "Cerrar sesión debe volver al formulario")
        XCTAssertFalse(app.buttons["account.signOut"].exists)
    }

    func testTabsAccessibleAndStatePreservedBetweenTabs() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-double", "identifiedReliable"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "La navegación principal debe ofrecer una barra de pestañas")

        let identifyTab = tabBar.buttons["Identificar"]
        let catchesTab = tabBar.buttons["Capturas"]
        XCTAssertTrue(identifyTab.exists, "La navegación principal debe ofrecer la pestaña Identificar")
        XCTAssertTrue(catchesTab.exists, "La navegación principal debe ofrecer la pestaña Capturas")

        let gallerySource = app.buttons["scanner.gallerySource"]
        XCTAssertTrue(gallerySource.waitForExistence(timeout: 10), "El tab Identificar debe mostrar el selector de fuente")
        gallerySource.tap()

        let identifying = app.otherElements["scanner.identifying"]
        XCTAssertTrue(identifying.waitForExistence(timeout: 10), "El estado de carga debe aparecer al identificar la imagen de galería")

        let speciesName = app.staticTexts["scanner.speciesName"]
        XCTAssertTrue(speciesName.waitForExistence(timeout: 10), "El resultado debe mostrar el nombre de la especie")
        XCTAssertTrue(speciesName.label.contains("Largemouth Bass"), "La especie identificada debe ser Largemouth Bass (identifiedReliable), obtenido: \(speciesName.label)")

        catchesTab.tap()

        let emptyState = app.otherElements["log.emptyState"]
        XCTAssertTrue(emptyState.waitForExistence(timeout: 10), "El tab Capturas con registro vacío debe mostrar el estado vacío")

        identifyTab.tap()

        XCTAssertTrue(speciesName.waitForExistence(timeout: 10), "Volver a Identificar debe conservar el resultado de la identificación")
        XCTAssertTrue(speciesName.label.contains("Largemouth Bass"), "El estado del escáner debe conservarse al alternar de tab, obtenido: \(speciesName.label)")
    }
}
