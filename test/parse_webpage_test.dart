import 'package:dr/wrapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dr/util.dart';

void main() {
  test('parseConfig reads the important profile values from the webpage', () {
    final config = Wrapper.parseConfig(source);

    expect(config.userId, 3539);
    expect(config.fullName, 'Tobias Bucci');
    expect(
      config.imgSource,
      'https://vinzentinum.digitalesregister.it/v2/theme/icons/profile_empty.png',
    );
    expect(config.autoLogoutSeconds, 300);
    expect(config.currentSemesterMaybe, isNull);
    expect(config.isStudentOrParent, isTrue);
  });

  test('parseConfig reports redirect pages as parse errors', () {
    expect(
      () => Wrapper.parseConfig(redirectSource),
      throwsA(isA<ParseException>()),
    );
  });
}

String source = r"""
<!DOCTYPE html>

<html class="no-js linen" lang="de">

<head class=" js no-flexbox no-touch hashchange rgba hsla multiplebgs backgroundsize borderradius boxshadow textshadow opacity cssanimations cssgradients csstransforms csstransforms3d csstransitions fontface generatedcontent boxsizing pointerevents no-details">
	<meta charset="utf-8">
	<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">

	<meta http-equiv="X-UA-Compatible" content="IE=edge,chrome=1">

	<title>Klassenbuch des Vinzentinums</title>

	<meta name="HandheldFriendly" content="True">
	<meta name="MobileOptimized" content="320">
	<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">


	<script>
		var currentUserId=3539;var currentUserName="st-debmic-03";var teachers = [];var rooms = [{"id":"1","name":"Werkraum"},{"id":"2","name":"3A"},{"id":"3","name":"3B"},{"id":"4","name":"1A"},{"id":"5","name":"1B"},{"id":"6","name":"2A"},{"id":"7","name":"2B"},{"id":"9","name":"4"},{"id":"10","name":"5"},{"id":"11","name":"6"},{"id":"12","name":"7"},{"id":"13","name":"8"},{"id":"14","name":"Chemieraum"},{"id":"15","name":"Physikraum"},{"id":"16","name":"Musikraum"},{"id":"17","name":"Biologieraum"},{"id":"18","name":"EDV-Raum 1"},{"id":"19","name":"Mittelschulbibliothek"},{"id":"20","name":"Oberschulbibliothek"},{"id":"21","name":"Festsaal"},{"id":"22","name":"Theatersaal"},{"id":"23","name":"Ausweichklasse"},{"id":"24","name":"Kunstraum"},{"id":"25","name":"Physikpraktikumsraum"},{"id":"26","name":"Turnhalle"},{"id":"27","name":"Chorproberaum KCH"},{"id":"28","name":"EDV-Raum 2 Tiefparterre"},{"id":"29","name":"Laptop 1"},{"id":"30","name":"Laptop 2"},{"id":"31","name":"Beamer 1"},{"id":"32","name":"Beamer 2"},{"id":"33","name":"Oberheadprojektor 1"},{"id":"34","name":"Oberheadprojektor 2"},{"id":"35","name":"Sportplatz"},{"id":"36","name":"Gruppenraum Turnhalle"},{"id":"37","name":"Fitnessraum"},{"id":"38","name":"Film-Kamera"},{"id":"39","name":"Fotoapparat"},{"id":"40","name":"Chorproberaum MCH"},{"id":"41","name":"Gruppenraum Tiefparterre T14"},{"id":"42","name":"Gruppenraum 1. Stock"}];var subjects = [{"id":"88","name":"Antike Mythologie","choiceSubject":"75","weight":"100"},{"id":"1","name":"Betragen","choiceSubject":"0","weight":"1"},{"id":"17","name":"Bewegung und Sport","choiceSubject":"0","weight":"2"},{"id":"86","name":"Bewegungsspass mit kleinen Spielen","choiceSubject":"73","weight":"100"},{"id":"6","name":"Deutsch","choiceSubject":"0","weight":"3"},{"id":"83","name":"Elektronikwerkstatt","choiceSubject":"70","weight":"0"},{"id":"84","name":"Elektronikwerkstatt 2","choiceSubject":"71","weight":"100"},{"id":"8","name":"Englisch","choiceSubject":"0","weight":"4"},{"id":"81","name":"Faszination Spielen","choiceSubject":"68","weight":"0"},{"id":"24","name":"FÜ","choiceSubject":"0","weight":"5"},{"id":"11","name":"Geografie","choiceSubject":"0","weight":"7"},{"id":"10","name":"Geschichte","choiceSubject":"0","weight":"6"},{"id":"20","name":"Griechisch","choiceSubject":"0","weight":"8"},{"id":"23","name":"IKT","choiceSubject":"0","weight":"9"},{"id":"82","name":"Italiano per tutti i giorni","choiceSubject":"69","weight":"0"},{"id":"87","name":"Italiano per tutti i giorni 2","choiceSubject":"74","weight":"100"},{"id":"7","name":"Italienisch","choiceSubject":"0","weight":"10"},{"id":"79","name":"KUGE-Schwerpunkt","choiceSubject":"0","weight":"0"},{"id":"15","name":"Kunst","choiceSubject":"0","weight":"11"},{"id":"19","name":"Latein","choiceSubject":"0","weight":"12"},{"id":"80","name":"Legomindstorms","choiceSubject":"67","weight":"0"},{"id":"85","name":"Legomindstorms 2","choiceSubject":"72","weight":"100"},{"id":"18","name":"Lernberatung","choiceSubject":"0","weight":"13"},{"id":"13","name":"Mathematik","choiceSubject":"0","weight":"14"},{"id":"16","name":"Musik","choiceSubject":"0","weight":"15"},{"id":"22","name":"Naturwissenschaften","choiceSubject":"0","weight":"16"},{"id":"78","name":"NATWI-Schwerpunkt","choiceSubject":"0","weight":"0"},{"id":"21","name":"Philosophie","choiceSubject":"0","weight":"17"},{"id":"14","name":"Physik","choiceSubject":"0","weight":"18"},{"id":"25","name":"Recht und Wirtschaft","choiceSubject":"0","weight":"19"},{"id":"5","name":"Religion","choiceSubject":"0","weight":"20"},{"id":"43","name":"Technik","choiceSubject":"0","weight":"21"},{"id":"56","name":"Z-Chor","choiceSubject":"0","weight":"0"},{"id":"53","name":"Z-Einkehrtag","choiceSubject":"0","weight":"0"},{"id":"68","name":"Z-Elternsprechtag","choiceSubject":"0","weight":"0"},{"id":"51","name":"Z-Herbstausflug","choiceSubject":"0","weight":"0"},{"id":"29","name":"Z-Klassenlehrerstunde","choiceSubject":"0","weight":"0"},{"id":"52","name":"Z-Lehrfahrt","choiceSubject":"0","weight":"0"},{"id":"58","name":"Z-Lernstunde","choiceSubject":"0","weight":"0"},{"id":"50","name":"Z-Maiausflug","choiceSubject":"0","weight":"0"},{"id":"54","name":"Z-Osterdienstag","choiceSubject":"0","weight":"0"},{"id":"77","name":"Z-PISA-Prüfung","choiceSubject":"0","weight":"0"},{"id":"63","name":"Z-Projektunterricht","choiceSubject":"0","weight":"0"},{"id":"57","name":"Z-Schueleraustausch","choiceSubject":"0","weight":"0"},{"id":"64","name":"Z-Weihnachtsfeier","choiceSubject":"0","weight":"0"},{"id":"49","name":"Z-Wintersporttag","choiceSubject":"0","weight":"0"}];var classes = [{"id":"52","name":"1A","choiceSubject":"0","belongsTo":"0"},{"id":"53","name":"1B","choiceSubject":"0","belongsTo":"0"},{"id":"54","name":"2A","choiceSubject":"0","belongsTo":"0"},{"id":"55","name":"2B","choiceSubject":"0","belongsTo":"0"},{"id":"56","name":"3A","choiceSubject":"0","belongsTo":"0"},{"id":"57","name":"3B","choiceSubject":"0","belongsTo":"0"},{"id":"58","name":"4K","choiceSubject":"0","belongsTo":"0"},{"id":"59","name":"5K","choiceSubject":"0","belongsTo":"0"},{"id":"60","name":"6K","choiceSubject":"0","belongsTo":"0"},{"id":"61","name":"7K","choiceSubject":"0","belongsTo":"0"},{"id":"66","name":"7K KUGE-Schwerpunkt","choiceSubject":"0","belongsTo":"61"},{"id":"65","name":"7K NATWI-Schwerpunkt","choiceSubject":"0","belongsTo":"61"},{"id":"62","name":"8K","choiceSubject":"0","belongsTo":"0"},{"id":"75","name":"Antike Mythologie","choiceSubject":"1","belongsTo":"0"},{"id":"73","name":"Bewegungsspass mit kleinen Spielen","choiceSubject":"1","belongsTo":"0"},{"id":"70","name":"Elektronikwerkstatt 1","choiceSubject":"1","belongsTo":"0"},{"id":"71","name":"Elektronikwerkstatt 2","choiceSubject":"1","belongsTo":"0"},{"id":"68","name":"Faszination Spielen","choiceSubject":"1","belongsTo":"0"},{"id":"69","name":"Italiano per tutti i giorni 1","choiceSubject":"1","belongsTo":"0"},{"id":"74","name":"Italiano per tutti i giorni 2","choiceSubject":"1","belongsTo":"0"},{"id":"67","name":"Legomindstorms 1","choiceSubject":"1","belongsTo":"0"},{"id":"72","name":"Legomindstorms 2","choiceSubject":"1","belongsTo":"0"}];var gradeTypes = [{"id":7,"name":"anderes"},{"id":4,"name":"Hausaufgabe"},{"id":6,"name":"Mitarbeit"},{"id":55,"name":"Online Hausaufgabe"},{"id":12,"name":"Praktische Arbeit"},{"id":1,"name":"Prüfung"},{"id":5,"name":"Referat"},{"id":3,"name":"Schularbeit"},{"id":2,"name":"Test"}];var observationTypes = [{"id":14,"name":"abgelenkt - anderweitig beschäftigt","oneclick":1},{"id":1,"name":"Anmerkung zum Verhalten","oneclick":0},{"id":5,"name":"Aussprachen, Persönliche Sprechstunden","oneclick":0},{"id":15,"name":"Begründung der negativen Endbewertung","oneclick":0},{"id":9,"name":"Bemerkung zur Vorbereitung","oneclick":0},{"id":8,"name":"Beobachtung","oneclick":0},{"id":6,"name":"Disziplinarvermerke","oneclick":0},{"id":17,"name":"für Prüfung entschuldigt","oneclick":1},{"id":10,"name":"gute Mitarbeit","oneclick":1},{"id":16,"name":"Hausaufgabe vergessen","oneclick":1},{"id":13,"name":"Lernunterlagen vergessen","oneclick":1},{"id":3,"name":"Lernvereinbarungen","oneclick":0},{"id":20,"name":"Minus","oneclick":1},{"id":19,"name":"Plus","oneclick":1},{"id":2,"name":"Rückmeldung zum Lernfortschritt","oneclick":0},{"id":11,"name":"schlechte Mitarbeit","oneclick":1},{"id":18,"name":"störendes Verhalten","oneclick":1},{"id":4,"name":"Stütz-, Aufhol-, Fördermaßnahmen","oneclick":0}];var config = {
					number_of_hours: 9,
					days_in_week: 5,
					competence_stars_enabled: true,
					competence_stars_scale: 5,
					competence_grade_decimals: false,
					minimum_grade: 3,
					auto_logout_seconds: 300,
				};var WWW = "https://vinzentinum.digitalesregister.it/v2/";var JSCOMPILER_PRESERVE = function() {};		var strings = {};
	</script>
</head>
<body class="reversed clearfix with-menu --main-navigation-show-mobile ">
<div class="v2-main-navigation main-navigation-show-mobile"><a href="#profile/view" class="hashlink item item-primary item-profile">
    <img id="navigationProfilePicture" src="https://vinzentinum.digitalesregister.it/v2/theme/icons/profile_empty.png">

    Michael Debertol<br><small>Profil bearbeiten</small>
    </a></div>
</body>
</html>
""";

const String redirectSource = """
<script type="text/javascript">
window.location = "https://vinzentinum.digitalesregister.it/v2/login";
</script>
""";
