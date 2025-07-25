window.CrystalDocs = (window.CrystalDocs || {});

CrystalDocs.base_path = (CrystalDocs.base_path || "");

CrystalDocs.searchIndex = (CrystalDocs.searchIndex || false);
CrystalDocs.MAX_RESULTS_DISPLAY = 140;

CrystalDocs.runQuery = function(query) {
  function searchType(type, query, results) {
    var matches = [];
    var matchedFields = [];
    var name = type.full_name;
    var i = name.lastIndexOf("::");
    if (i > 0) {
      name = name.substring(i + 2);
    }
    var nameMatches = query.matches(name);
    if (nameMatches){
      matches = matches.concat(nameMatches);
      matchedFields.push("name");
    }

    var namespaceMatches = query.matchesNamespace(type.full_name);
    if(namespaceMatches){
      matches = matches.concat(namespaceMatches);
      matchedFields.push("name");
    }

    var docMatches = query.matches(type.doc);
    if(docMatches){
      matches = matches.concat(docMatches);
      matchedFields.push("doc");
    }
    if (matches.length > 0) {
      results.push({
        id: type.html_id,
        result_type: "type",
        kind: type.kind,
        name: name,
        full_name: type.full_name,
        href: type.path,
        summary: type.summary,
        matched_fields: matchedFields,
        matched_terms: matches
      });
    }

    if (type.instance_methods) {
      type.instance_methods.forEach(function(method) {
        searchMethod(method, type, "instance_method", query, results);
      })
    }
    if (type.class_methods) {
      type.class_methods.forEach(function(method) {
        searchMethod(method, type, "class_method", query, results);
      })
    }
    if (type.constructors) {
      type.constructors.forEach(function(constructor) {
        searchMethod(constructor, type, "constructor", query, results);
      })
    }
    if (type.macros) {
      type.macros.forEach(function(macro) {
        searchMethod(macro, type, "macro", query, results);
      })
    }
    if (type.constants) {
      type.constants.forEach(function(constant){
        searchConstant(constant, type, query, results);
      });
    }
    if (type.types) {
      type.types.forEach(function(subtype){
        searchType(subtype, query, results);
      });
    }
  };

  function searchMethod(method, type, kind, query, results) {
    var matches = [];
    var matchedFields = [];
    var nameMatches = query.matchesMethod(method.name, kind, type);
    if (nameMatches){
      matches = matches.concat(nameMatches);
      matchedFields.push("name");
    }

    if (method.args) {
      method.args.forEach(function(arg){
        var argMatches = query.matches(arg.external_name);
        if (argMatches) {
          matches = matches.concat(argMatches);
          matchedFields.push("args");
        }
      });
    }

    var docMatches = query.matches(type.doc);
    if(docMatches){
      matches = matches.concat(docMatches);
      matchedFields.push("doc");
    }

    if (matches.length > 0) {
      var typeMatches = query.matches(type.full_name);
      if (typeMatches) {
        matchedFields.push("type");
        matches = matches.concat(typeMatches);
      }
      results.push({
        id: method.html_id,
        type: type.full_name,
        result_type: kind,
        name: method.name,
        full_name: type.full_name + "#" + method.name,
        args_string: method.args_string,
        summary: method.summary,
        href: type.path + "#" + method.html_id,
        matched_fields: matchedFields,
        matched_terms: matches
      });
    }
  }

  function searchConstant(constant, type, query, results) {
    var matches = [];
    var matchedFields = [];
    var nameMatches = query.matches(constant.name);
    if (nameMatches){
      matches = matches.concat(nameMatches);
      matchedFields.push("name");
    }
    var docMatches = query.matches(constant.doc);
    if(docMatches){
      matches = matches.concat(docMatches);
      matchedFields.push("doc");
    }
    if (matches.length > 0) {
      var typeMatches = query.matches(type.full_name);
      if (typeMatches) {
        matchedFields.push("type");
        matches = matches.concat(typeMatches);
      }
      results.push({
        id: constant.id,
        type: type.full_name,
        result_type: "constant",
        name: constant.name,
        full_name: type.full_name + "#" + constant.name,
        value: constant.value,
        summary: constant.summary,
        href: type.path + "#" + constant.id,
        matched_fields: matchedFields,
        matched_terms: matches
      });
    }
  }

  var results = [];
  searchType(CrystalDocs.searchIndex.program, query, results);
  return results;
};

CrystalDocs.rankResults = function(results, query) {
  function uniqueArray(ar) {
    var j = {};

    ar.forEach(function(v) {
      j[v + "::" + typeof v] = v;
    });

    return Object.keys(j).map(function(v) {
      return j[v];
    });
  }

  results = results.sort(function(a, b) {
    var matchedTermsDiff = uniqueArray(b.matched_terms).length - uniqueArray(a.matched_terms).length;
    var aHasDocs = b.matched_fields.includes("doc");
    var bHasDocs = b.matched_fields.includes("doc");

    var aOnlyDocs = aHasDocs && a.matched_fields.length == 1;
    var bOnlyDocs = bHasDocs && b.matched_fields.length == 1;

    if (a.result_type == "type" && b.result_type != "type" && !aOnlyDocs) {
      if(CrystalDocs.DEBUG) { console.log("a is type b not"); }
      return -1;
    } else if (b.result_type == "type" && a.result_type != "type" && !bOnlyDocs) {
      if(CrystalDocs.DEBUG) { console.log("b is type, a not"); }
      return 1;
    }
    if (a.matched_fields.includes("name")) {
      if (b.matched_fields.includes("name")) {
        var a_name = (CrystalDocs.prefixForType(a.result_type) || "") + ((a.result_type == "type") ? a.full_name : a.name);
        var b_name = (CrystalDocs.prefixForType(b.result_type) || "") + ((b.result_type == "type") ? b.full_name : b.name);
        a_name = a_name.toLowerCase();
        b_name = b_name.toLowerCase();
        for(var i = 0; i < query.normalizedTerms.length; i++) {
          var term = query.terms[i].replace(/^::?|::?$/, "");
          var a_orig_index = a_name.indexOf(term);
          var b_orig_index = b_name.indexOf(term);
          if(CrystalDocs.DEBUG) { console.log("term: " + term + " a: " + a_name + " b: " + b_name); }
          if(CrystalDocs.DEBUG) { console.log(a_orig_index, b_orig_index, a_orig_index - b_orig_index); }
          if (a_orig_index >= 0) {
            if (b_orig_index >= 0) {
              if(CrystalDocs.DEBUG) { console.log("both have exact match", a_orig_index > b_orig_index ? -1 : 1); }
              if(a_orig_index != b_orig_index) {
                if(CrystalDocs.DEBUG) { console.log("both have exact match at different positions", a_orig_index > b_orig_index ? 1 : -1); }
                return a_orig_index > b_orig_index ? 1 : -1;
              }
            } else {
              if(CrystalDocs.DEBUG) { console.log("a has exact match, b not"); }
              return -1;
            }
          } else if (b_orig_index >= 0) {
            if(CrystalDocs.DEBUG) { console.log("b has exact match, a not"); }
            return 1;
          }
        }
      } else {
        if(CrystalDocs.DEBUG) { console.log("a has match in name, b not"); }
        return -1;
      }
    } else if (
      !a.matched_fields.includes("name") &&
      b.matched_fields.includes("name")
    ) {
      return 1;
    }

    if (matchedTermsDiff != 0 || (aHasDocs != bHasDocs)) {
      if(CrystalDocs.DEBUG) { console.log("matchedTermsDiff: " + matchedTermsDiff, aHasDocs, bHasDocs); }
      return matchedTermsDiff;
    }

    var matchedFieldsDiff = b.matched_fields.length - a.matched_fields.length;
    if (matchedFieldsDiff != 0) {
      if(CrystalDocs.DEBUG) { console.log("matched to different number of fields: " + matchedFieldsDiff); }
      return matchedFieldsDiff > 0 ? 1 : -1;
    }

    var nameCompare = a.name.localeCompare(b.name);
    if(nameCompare != 0){
      if(CrystalDocs.DEBUG) { console.log("nameCompare resulted in: " + a.name + "<=>" + b.name + ": " + nameCompare); }
      return nameCompare > 0 ? 1 : -1;
    }

    if(a.matched_fields.includes("args") && b.matched_fields.includes("args")) {
      for(var i = 0; i < query.terms.length; i++) {
        var term = query.terms[i];
        var aIndex = a.args_string.indexOf(term);
        var bIndex = b.args_string.indexOf(term);
        if(CrystalDocs.DEBUG) { console.log("index of " + term + " in args_string: " + aIndex + " - " + bIndex); }
        if(aIndex >= 0){
          if(bIndex >= 0){
            if(aIndex != bIndex){
              return aIndex > bIndex ? 1 : -1;
            }
          }else{
            return -1;
          }
        }else if(bIndex >= 0) {
          return 1;
        }
      }
    }

    return 0;
  });

  if (results.length > 1) {
    // if we have more than two search terms, only include results with the most matches
    var bestMatchedTerms = uniqueArray(results[0].matched_terms).length;

    results = results.filter(function(result) {
      return uniqueArray(result.matched_terms).length + 1 >= bestMatchedTerms;
    });
  }
  return results;
};

CrystalDocs.prefixForType = function(type) {
  switch (type) {
    case "instance_method":
      return "#";

    case "class_method":
    case "macro":
    case "constructor":
      return ".";

    default:
      return false;
  }
};

CrystalDocs.displaySearchResults = function(results, query) {
  function sanitize(html){
    return html.replace(/<(?!\/?code)[^>]+>/g, "");
  }

  // limit results
  if (results.length > CrystalDocs.MAX_RESULTS_DISPLAY) {
    results = results.slice(0, CrystalDocs.MAX_RESULTS_DISPLAY);
  }

  var $frag = document.createDocumentFragment();
  var $resultsElem = document.querySelector(".search-list");
  $resultsElem.innerHTML = "<!--" + JSON.stringify(query) + "-->";

  results.forEach(function(result, i) {
    var url = CrystalDocs.base_path + result.href;
    var type = false;

    var title = query.highlight(result.result_type == "type" ? result.full_name : result.name);

    var prefix = CrystalDocs.prefixForType(result.result_type);
    if (prefix) {
      title = "<b>" + prefix + "</b>" + title;
    }

    title = "<strong>" + title + "</strong>";

    if (result.args_string) {
      title +=
        "<span class=\"args\">" + query.highlight(result.args_string) + "</span>";
    }

    $elem = document.createElement("li");
    $elem.className = "search-result search-result--" + result.result_type;
    $elem.dataset.href = url;
    $elem.setAttribute("title", result.full_name + " docs page");

    var $title = document.createElement("div");
    $title.setAttribute("class", "search-result__title");
    var $titleLink = document.createElement("a");
    $titleLink.setAttribute("href", url);

    $titleLink.innerHTML = title;
    $title.appendChild($titleLink);
    $elem.appendChild($title);
    $elem.addEventListener("click", function() {
      $titleLink.click();
    });

    if (result.result_type !== "type") {
      var $type = document.createElement("div");
      $type.setAttribute("class", "search-result__type");
      $type.innerHTML = query.highlight(result.type);
      $elem.appendChild($type);
    }

    if(result.summary){
      var $doc = document.createElement("div");
      $doc.setAttribute("class", "search-result__doc");
      $doc.innerHTML = query.highlight(sanitize(result.summary));
      $elem.appendChild($doc);
    }

    $elem.appendChild(document.createComment(JSON.stringify(result)));
    $frag.appendChild($elem);
  });

  $resultsElem.appendChild($frag);

  CrystalDocs.toggleResultsList(true);
};

CrystalDocs.toggleResultsList = function(visible) {
  if (visible) {
    document.querySelector(".types-list").classList.add("hidden");
    document.querySelector(".search-results").classList.remove("hidden");
  } else {
    document.querySelector(".types-list").classList.remove("hidden");
    document.querySelector(".search-results").classList.add("hidden");
  }
};

CrystalDocs.Query = function(string) {
  this.original = string;
  this.terms = string.split(/\s+/).filter(function(word) {
    return CrystalDocs.Query.stripModifiers(word).length > 0;
  });

  var normalized = this.terms.map(CrystalDocs.Query.normalizeTerm);
  this.normalizedTerms = normalized;

  function runMatcher(field, matcher) {
    if (!field) {
      return false;
    }
    var normalizedValue = CrystalDocs.Query.normalizeTerm(field);

    var matches = [];
    normalized.forEach(function(term) {
      if (matcher(normalizedValue, term)) {
        matches.push(term);
      }
    });
    return matches.length > 0 ? matches : false;
  }

  this.matches = function(field) {
    return runMatcher(field, function(normalized, term) {
      if (term[0] == "#" || term[0] == ".") {
        return false;
      }
      return normalized.indexOf(term) >= 0;
    });
  };

  function namespaceMatcher(normalized, term){
    var i = term.indexOf(":");
    if(i >= 0){
      term = term.replace(/^::?|::?$/, "");
      var index = normalized.indexOf(term);
      if((index == 0) || (index > 0 && normalized[index-1] == ":")){
        return true;
      }
    }
    return false;
  }
  this.matchesMethod = function(name, kind, type) {
    return runMatcher(name, function(normalized, term) {
      var i = term.indexOf("#");
      if(i >= 0){
        if (kind != "instance_method") {
          return false;
        }
      }else{
        i = term.indexOf(".");
        if(i >= 0){
          if (kind != "class_method" && kind != "macro" && kind != "constructor") {
            return false;
          }
        }else{
          //neither # nor .
          if(term.indexOf(":") && namespaceMatcher(normalized, term)){
            return true;
          }
        }
      }

      var methodName = term;
      if(i >= 0){
        var termType = term.substring(0, i);
        methodName = term.substring(i+1);

        if(termType != "") {
          if(CrystalDocs.Query.normalizeTerm(type.full_name).indexOf(termType) < 0){
            return false;
          }
        }
      }
      return normalized.indexOf(methodName) >= 0;
    });
  };

  this.matchesNamespace = function(namespace){
    return runMatcher(namespace, namespaceMatcher);
  };

  this.highlight = function(string) {
    if (typeof string == "undefined") {
      return "";
    }
    function escapeRegExp(s) {
      return s.replace(/[.*+?\^${}()|\[\]\\]/g, "\\$&").replace(/^[#\.:]+/, "");
    }
    return string.replace(
      new RegExp("(" + this.normalizedTerms.map(escapeRegExp).join("|") + ")", "gi"),
      "<mark>$1</mark>"
    );
  };
};
CrystalDocs.Query.normalizeTerm = function(term) {
  return term.toLowerCase();
};
CrystalDocs.Query.stripModifiers = function(term) {
  switch (term[0]) {
    case "#":
    case ".":
    case ":":
      return term.substr(1);

    default:
      return term;
  }
}

CrystalDocs.search = function(string) {
  if(!CrystalDocs.searchIndex) {
    console.log("CrystalDocs search index not initialized, delaying search");

    document.addEventListener("CrystalDocs:loaded", function listener(){
      document.removeEventListener("CrystalDocs:loaded", listener);
      CrystalDocs.search(string);
    });
    return;
  }

  document.dispatchEvent(new Event("CrystalDocs:searchStarted"));

  var query = new CrystalDocs.Query(string);
  var results = CrystalDocs.runQuery(query);
  results = CrystalDocs.rankResults(results, query);
  CrystalDocs.displaySearchResults(results, query);

  document.dispatchEvent(new Event("CrystalDocs:searchPerformed"));
};

CrystalDocs.initializeIndex = function(data) {
  CrystalDocs.searchIndex = data;

  document.dispatchEvent(new Event("CrystalDocs:loaded"));
};

CrystalDocs.loadIndex = function() {
  function loadJSON(file, callback) {
    var xobj = new XMLHttpRequest();
    xobj.overrideMimeType("application/json");
    xobj.open("GET", file, true);
    xobj.onreadystatechange = function() {
      if (xobj.readyState == 4 && xobj.status == "200") {
        callback(xobj.responseText);
      }
    };
    xobj.send(null);
  }

  function loadScript(file) {
    script = document.createElement("script");
    script.src = file;
    document.body.appendChild(script);
  }

  function parseJSON(json) {
    CrystalDocs.initializeIndex(JSON.parse(json));
  }

  for(var i = 0; i < document.scripts.length; i++){
    var script = document.scripts[i];
    if (script.src && script.src.indexOf("js/doc.js") >= 0) {
      if (script.src.indexOf("file://") == 0) {
        // We need to support JSONP files for the search to work on local file system.
        var jsonPath = script.src.replace("js/doc.js", "search-index.js");
        loadScript(jsonPath);
        return;
      } else {
        var jsonPath = script.src.replace("js/doc.js", "index.json");
        loadJSON(jsonPath, parseJSON);
        return;
      }
    }
  }
  console.error("Could not find location of js/doc.js");
};

// Callback for jsonp
function crystal_doc_search_index_callback(data) {
  CrystalDocs.initializeIndex(data);
}

Navigator = function(sidebar, searchInput, list, leaveSearchScope){
  this.list = list;
  var self = this;

  var performingSearch = false;

  document.addEventListener('CrystalDocs:searchStarted', function(){
    performingSearch = true;
  });
  document.addEventListener('CrystalDocs:searchDebounceStarted', function(){
    performingSearch = true;
  });
  document.addEventListener('CrystalDocs:searchPerformed', function(){
    performingSearch = false;
  });
  document.addEventListener('CrystalDocs:searchDebounceStopped', function(event){
    performingSearch = false;
  });

  function delayWhileSearching(callback) {
    if(performingSearch){
      document.addEventListener('CrystalDocs:searchPerformed', function listener(){
        document.removeEventListener('CrystalDocs:searchPerformed', listener);

        // add some delay to let search results display kick in
        setTimeout(callback, 100);
      });
    }else{
      callback();
    }
  }

  function clearMoveTimeout() {
    clearTimeout(self.moveTimeout);
    self.moveTimeout = null;
  }

  function startMoveTimeout(upwards){
    /*if(self.moveTimeout) {
      clearMoveTimeout();
    }

    var go = function() {
      if (!self.moveTimeout) return;
      self.move(upwards);
      self.moveTimeout = setTimeout(go, 600);
    };
    self.moveTimeout = setTimeout(go, 800);*/
  }

  function scrollCenter(element) {
    var rect = element.getBoundingClientRect();
    var middle = sidebar.clientHeight / 2;
    sidebar.scrollTop += rect.top + rect.height / 2 - middle;
  }

  var move = this.move = function(upwards){
    if(!this.current){
      this.highlightFirst();
      return true;
    }
    var next = upwards ? this.current.previousElementSibling : this.current.nextElementSibling;
    if(next && next.classList) {
      this.highlight(next);
      scrollCenter(next);
      return true;
    }
    return false;
  };

  this.moveRight = function(){
  };
  this.moveLeft = function(){
  };

  this.highlight = function(elem) {
    if(!elem){
      return;
    }
    this.removeHighlight();

    this.current = elem;
    this.current.classList.add("current");
  };

  this.highlightFirst = function(){
    this.highlight(this.list.querySelector('li:first-child'));
  };

  this.removeHighlight = function() {
    if(this.current){
      this.current.classList.remove("current");
    }
    this.current = null;
  }

  this.openSelectedResult = function() {
    if(this.current) {
      this.current.click();
    }
  }

  this.focus = function() {
    searchInput.focus();
    searchInput.select();
    this.highlightFirst();
  }

  function handleKeyUp(event) {
    switch(event.key) {
      case "ArrowUp":
      case "ArrowDown":
      case "i":
      case "j":
      case "k":
      case "l":
      case "c":
      case "h":
      case "t":
      case "n":
      event.stopPropagation();
      clearMoveTimeout();
    }
  }

  function handleKeyDown(event) {
    switch(event.key) {
      case "Enter":
        event.stopPropagation();
        event.preventDefault();
        leaveSearchScope();
        self.openSelectedResult();
        break;
      case "Escape":
        event.stopPropagation();
        event.preventDefault();
        leaveSearchScope();
        break;
      case "j":
      case "c":
      case "ArrowUp":
        if(event.ctrlKey || event.key == "ArrowUp") {
          event.stopPropagation();
          self.move(true);
          startMoveTimeout(true);
        }
        break;
      case "k":
      case "h":
      case "ArrowDown":
        if(event.ctrlKey || event.key == "ArrowDown") {
          event.stopPropagation();
          self.move(false);
          startMoveTimeout(false);
        }
        break;
      case "k":
      case "t":
      case "ArrowLeft":
        if(event.ctrlKey || event.key == "ArrowLeft") {
          event.stopPropagation();
          self.moveLeft();
        }
        break;
      case "l":
      case "n":
      case "ArrowRight":
        if(event.ctrlKey || event.key == "ArrowRight") {
          event.stopPropagation();
          self.moveRight();
        }
        break;
    }
  }

  function handleInputKeyUp(event) {
    switch(event.key) {
      case "ArrowUp":
      case "ArrowDown":
      event.stopPropagation();
      event.preventDefault();
      clearMoveTimeout();
    }
  }

  function handleInputKeyDown(event) {
    switch(event.key) {
      case "Enter":
        event.stopPropagation();
        event.preventDefault();
        delayWhileSearching(function(){
          self.openSelectedResult();
          leaveSearchScope();
        });
        break;
      case "Escape":
        event.stopPropagation();
        event.preventDefault();
        // remove focus from search input
        leaveSearchScope();
        sidebar.focus();
        break;
      case "ArrowUp":
        event.stopPropagation();
        event.preventDefault();
        self.move(true);
        startMoveTimeout(true);
        break;

      case "ArrowDown":
        event.stopPropagation();
        event.preventDefault();
        self.move(false);
        startMoveTimeout(false);
        break;
    }
  }

  sidebar.tabIndex = 100; // set tabIndex to enable keylistener
  sidebar.addEventListener('keyup', function(event) {
    handleKeyUp(event);
  });
  sidebar.addEventListener('keydown', function(event) {
    handleKeyDown(event);
  });
  searchInput.addEventListener('keydown', function(event) {
    handleInputKeyDown(event);
  });
  searchInput.addEventListener('keyup', function(event) {
    handleInputKeyUp(event);
  });
  this.move();
};

CrystalDocs.initializeVersions = function () {
  function loadJSON(file, callback) {
    var xobj = new XMLHttpRequest();
    xobj.overrideMimeType("application/json");
    xobj.open("GET", file, true);
    xobj.onreadystatechange = function() {
      if (xobj.readyState == 4 && xobj.status == "200") {
        callback(xobj.responseText);
      }
    };
    xobj.send(null);
  }

  function parseJSON(json) {
    CrystalDocs.loadConfig(JSON.parse(json));
  }

  $elem = document.querySelector("html > head > meta[name=\"crystal_docs.json_config_url\"]")
  if ($elem == undefined) {
    return
  }
  jsonURL = $elem.getAttribute("content")
  if (jsonURL && jsonURL != "") {
    loadJSON(jsonURL, parseJSON);
  }
}

CrystalDocs.loadConfig = function (config) {
  var projectVersions = config["versions"]
  var currentVersion = document.querySelector("html > head > meta[name=\"crystal_docs.project_version\"]").getAttribute("content")

  var currentVersionInList = projectVersions.find(function (element) {
    return element.name == currentVersion
  })

  if (!currentVersionInList) {
    projectVersions.unshift({ name: currentVersion, url: '#' })
  }

  $version = document.querySelector(".project-summary > .project-version")
  $version.innerHTML = ""

  $select = document.createElement("select")
  $select.classList.add("project-versions-nav")
  $select.addEventListener("change", function () {
    window.location.href = this.value
  })
  projectVersions.forEach(function (version) {
    $item = document.createElement("option")
    $item.setAttribute("value", version.url)
    $item.append(document.createTextNode(version.name))

    if (version.name == currentVersion) {
      $item.setAttribute("selected", true)
      $item.setAttribute("disabled", true)
    }
    $select.append($item)
  });
  $form = document.createElement("form")
  $form.setAttribute("autocomplete", "off")
  $form.append($select)
  $version.append($form)
}

document.addEventListener("DOMContentLoaded", function () {
  CrystalDocs.initializeVersions()
})

var UsageModal = function(title, content) {
  var $body = document.body;
  var self = this;
  var $modalBackground = document.createElement("div");
  $modalBackground.classList.add("modal-background");
  var $usageModal = document.createElement("div");
  $usageModal.classList.add("usage-modal");
  $modalBackground.appendChild($usageModal);
  var $title = document.createElement("h3");
  $title.classList.add("modal-title");
  $title.innerHTML = title
  $usageModal.appendChild($title);
  var $closeButton = document.createElement("span");
  $closeButton.classList.add("close-button");
  $closeButton.setAttribute("title", "Close modal");
  $closeButton.innerText = '×';
  $usageModal.appendChild($closeButton);
  $usageModal.insertAdjacentHTML("beforeend", content);

  $modalBackground.addEventListener('click', function(event) {
    var element = event.target || event.srcElement;

    if(element == $modalBackground) {
      self.hide();
    }
  });
  $closeButton.addEventListener('click', function(event) {
    self.hide();
  });

  $body.insertAdjacentElement('beforeend', $modalBackground);

  this.show = function(){
    $body.classList.add("js-modal-visible");
  };
  this.hide = function(){
    $body.classList.remove("js-modal-visible");
  };
  this.isVisible = function(){
    return $body.classList.contains("js-modal-visible");
  }
}


document.addEventListener('DOMContentLoaded', function() {
  var sessionStorage;
  try {
    sessionStorage = window.sessionStorage;
  } catch (e) { }
  if(!sessionStorage) {
    sessionStorage = {
      setItem: function() {},
      getItem: function() {},
      removeItem: function() {}
    };
  }

  var repositoryName = document.querySelector('[name=repository-name]').getAttribute('content');
  var typesList = document.querySelector('.types-list');
  var searchInput = document.querySelector('.search-input');
  var parents = document.querySelectorAll('.types-list li.parent');

  var scrollSidebarToOpenType = function(){
    var openTypes = typesList.querySelectorAll('.current');
    if (openTypes.length > 0) {
      var lastOpenType = openTypes[openTypes.length - 1];
      lastOpenType.scrollIntoView();
    }
  }

  scrollSidebarToOpenType();

  var setPersistentSearchQuery = function(value){
    sessionStorage.setItem(repositoryName + '::search-input:value', value);
  }

  for(var i = 0; i < parents.length; i++) {
    var _parent = parents[i];
    _parent.addEventListener('click', function(e) {
      e.stopPropagation();

      if(e.target.tagName.toLowerCase() == 'li') {
        if(e.target.className.match(/open/)) {
          sessionStorage.removeItem(e.target.getAttribute('data-id'));
          e.target.className = e.target.className.replace(/ +open/g, '');
        } else {
          sessionStorage.setItem(e.target.getAttribute('data-id'), '1');
          if(e.target.className.indexOf('open') == -1) {
            e.target.className += ' open';
          }
        }
      }
    });

    if(sessionStorage.getItem(_parent.getAttribute('data-id')) == '1') {
      _parent.className += ' open';
    }
  }

  var leaveSearchScope = function(){
    CrystalDocs.toggleResultsList(false);
    window.focus();
  }

  var navigator = new Navigator(document.querySelector('.types-list'), searchInput, document.querySelector(".search-results"), leaveSearchScope);

  CrystalDocs.loadIndex();
  var searchTimeout;
  var lastSearchText = false;
  var performSearch = function() {
    document.dispatchEvent(new Event("CrystalDocs:searchDebounceStarted"));

    clearTimeout(searchTimeout);
    searchTimeout = setTimeout(function() {
      var text = searchInput.value;

      if(text == "") {
        CrystalDocs.toggleResultsList(false);
      }else if(text == lastSearchText){
        document.dispatchEvent(new Event("CrystalDocs:searchDebounceStopped"));
      }else{
        CrystalDocs.search(text);
        navigator.highlightFirst();
        searchInput.focus();
      }
      lastSearchText = text;
      setPersistentSearchQuery(text);
    }, 200);
  };

  if(location.hash.length > 3 && location.hash.substring(0,3) == "#q="){
    // allows directly linking a search query which is then executed on the client
    // this comes handy for establishing a custom browser search engine with https://crystal-lang.org/api/#q=%s as a search URL
    // TODO: Add OpenSearch description
    var searchQuery = location.hash.substring(3);
    history.pushState({searchQuery: searchQuery}, "Search for " + searchQuery, location.href.replace(/#q=.*/, ""));
    searchInput.value = searchQuery;
    document.addEventListener('CrystalDocs:loaded', performSearch);
  }

  if (searchInput.value.length == 0) {
    var searchText = sessionStorage.getItem(repositoryName + '::search-input:value');
    if(searchText){
      searchInput.value = searchText;
    }
  }
  searchInput.addEventListener('keyup', performSearch);
  searchInput.addEventListener('input', performSearch);

  var usageModal = new UsageModal('Keyboard Shortcuts', '' +
      '<ul class="usage-list">' +
      '  <li>' +
      '    <span class="usage-key">' +
      '      <kbd>s</kbd>,' +
      '      <kbd>/</kbd>' +
      '    </span>' +
      '    Search' +
      '  </li>' +
      '  <li>' +
      '    <kbd class="usage-key">Esc</kbd>' +
      '    Abort search / Close modal' +
      '  </li>' +
      '  <li>' +
      '    <span class="usage-key">' +
      '      <kbd>⇨</kbd>,' +
      '      <kbd>Enter</kbd>' +
      '    </span>' +
      '    Open highlighted result' +
      '  </li>' +
      '  <li>' +
      '    <span class="usage-key">' +
      '      <kbd>⇧</kbd>,' +
      '      <kbd>Ctrl+j</kbd>' +
      '    </span>' +
      '    Select previous result' +
      '  </li>' +
      '  <li>' +
      '    <span class="usage-key">' +
      '      <kbd>⇩</kbd>,' +
      '      <kbd>Ctrl+k</kbd>' +
      '    </span>' +
      '    Select next result' +
      '  </li>' +
      '  <li>' +
      '    <kbd class="usage-key">?</kbd>' +
      '    Show usage info' +
      '  </li>' +
      '</ul>'
    );

  function handleShortkeys(event) {
    var element = event.target || event.srcElement;

    if(element.tagName == "INPUT" || element.tagName == "TEXTAREA" || element.parentElement.tagName == "TEXTAREA"){
      return;
    }

    switch(event.key) {
      case "?":
        usageModal.show();
        break;

      case "Escape":
        usageModal.hide();
        break;

      case "s":
      case "/":
        if(usageModal.isVisible()) {
          return;
        }
        event.stopPropagation();
        navigator.focus();
        performSearch();
        break;
    }
  }

  document.addEventListener('keyup', handleShortkeys);

  var scrollToEntryFromLocationHash = function() {
    var hash = window.location.hash;
    if (hash) {
      var targetAnchor = decodeURI(hash.substr(1));
      var targetEl = document.getElementById(targetAnchor)
      if (targetEl) {
        targetEl.offsetParent.scrollTop = targetEl.offsetTop;
      }
    }
  };
  window.addEventListener("hashchange", scrollToEntryFromLocationHash, false);
  scrollToEntryFromLocationHash();
});
