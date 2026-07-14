enum Weather { sunny, cloudy, rainy, heavyRain, typhoon }

extension WeatherLabel on Weather {
  String get label => switch (this) {
    Weather.sunny => '晴',
    Weather.cloudy => '陰',
    Weather.rainy => '雨',
    Weather.heavyRain => '豪大雨',
    Weather.typhoon => '颱',
  };

  static Weather fromLabel(String label) =>
      Weather.values.firstWhere((w) => w.label == label);
}
